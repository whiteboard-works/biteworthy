# frozen_string_literal: true

module Ingestion
  # Stage one: vision extraction.
  #
  # Reads the run's attached input(s), calls Anthropic vision with the menu
  # extraction prompt, validates the response against
  # MENU_EXTRACTION_SCHEMA, materializes one IngestionItem per extracted
  # dish, and hands off to ResolveRun.
  #
  # This is the pipeline's one heavyweight LLM call and it legitimately
  # takes tens of seconds, which is why it runs in a job rather than inline
  # in a tool call — see Tools::Ingestion::StartMenuScan.
  #
  # The body lives here rather than in ExtractMenuJob so the job is a thin
  # wrapper and the logic is callable directly from a spec or a console.
  #
  # Idempotent: a run already past :extracting is a no-op.
  class ExtractRun
    include TimedAnthropicCall

    # The client default is 8,000, which was never chosen for this call —
    # it is the shared default, and this is the one caller that emits a
    # long structured document. A dense menu overran it and the run was
    # reported as a *schema* failure, because a response cut off at the
    # limit is also unparseable JSON.
    #
    # 16,000 rather than the model's 128,000 ceiling, deliberately.
    # `max_tokens` is a cap, not a target, so a bigger number costs
    # nothing when unused — but it is also the only thing bounding how
    # long one non-streaming call can take, and `ANTHROPIC_READ_TIMEOUT`
    # is 240s. At Sonnet's throughput 16k lands inside that; 128k does
    # not, so the "fix" would trade a truncated response for a socket
    # timeout, which is the same failure with a worse error message.
    # Anything genuinely larger belongs in more than one call.
    MAX_OUTPUT_TOKENS = 16_000

    def self.call(run) = new(run).call

    def initialize(run)
      @run = run
    end

    def call
      return if @run.resolving? || @run.staged? || @run.published? || @run.failed?

      # Being called before the run entered :extracting means we were
      # dispatched by hand; flip the state ourselves so the audit trail in
      # state_history stays honest.
      @run.transition_to!(:extracting) if @run.queued?

      blobs = Array(@run.inputs.attached? ? @run.inputs.blobs : [])
      if blobs.empty?
        @run.fail!("no_inputs_attached")
        return
      end

      # A previous attempt may already have paid for the vision call — it is
      # the most expensive thing the product does, and `ApplicationJob`
      # retries every StandardError three times. Anything raised below this
      # point (a materialize failure, a lost connection mid-transition)
      # leaves the run in :extracting, so the retry lands right back here.
      # Without this the retry re-bills the call; `docs/ingestion.md` claims
      # each stage is idempotent and this is what makes that true of the one
      # stage where being wrong costs money.
      if @run.staging.present?
        result = @run.staging
      else
        out = timed_anthropic_call(@run, api_error: "anthropic_api_error",
                                         validation_error: "schema_validation_failed") do |client|
          client.messages_create(
            system:          ExtractMenuPrompt.system(client),
            messages:        ExtractMenuPrompt.user_messages(client, blobs),
            max_tokens:      MAX_OUTPUT_TOKENS,
            # Constrained, not merely requested. Until now the schema was
            # a prompt instruction plus a post-hoc check, which catches
            # malformed output but cannot prevent it — and one of the two
            # live failures was exactly that: a stray `>` where a `:`
            # belonged, 4 KB into an otherwise fine response, far too
            # early to be a truncation. Grammar-constrained decoding
            # cannot emit that.
            output_config:   { format: { type: "json_schema",
                                         schema: SchemaForRequest.derive(MenuExtractionSchema) } },
            # Still validated after: the wire schema constrains shape, the
            # full one enforces the values structured outputs will not
            # carry (minimums, lengths).
            response_schema: MenuExtractionSchema
          )
        end
        return if out.nil?

        result, elapsed_ms = out
        # Saved before the transaction below, not inside it: a rollback there
        # must not also discard the answer we just bought.
        @run.update!(staging: result, latency_ms: elapsed_ms)
      end

      # Materialize the dishes NOW, with empty ingredient/tag payloads, so a
      # caller sees real items seconds after extraction; ResolveRun enriches
      # them in place. Atomic with the transition so a run never sits in
      # :resolving without its items.
      @run.transaction do
        materialize_items!
        @run.transition_to!(:resolving)
      end

      ResolveItemsJob.perform_later(@run.id)
    end

    private

    # One IngestionItem per extracted dish, in flat order, carrying the
    # position so the resolve stage can write its indexed results back onto
    # the right row.
    #
    # Add-on guard: the extraction prompt nests add-on/upsell lines under
    # their parent dish, but the model sometimes still emits an "Add X" line
    # as a top-level item. Those fold into the PREVIOUS item's
    # addons_payload here (source: "guard") instead of materializing — an
    # upsell line must never publish as a dish. First-in-section has no
    # parent to attach to, so it materializes normally.
    def materialize_items!
      position = 0
      Array(@run.staging["sections"]).each do |section|
        previous = nil
        Array(section["items"]).each do |item|
          if previous && addon_line?(item["name"])
            previous.update!(addons_payload: previous.addons_payload + [guard_addon_row(item)])
            next
          end

          previous = @run.ingestion_items.create!(
            name:           item["name"],
            description:    item["description"],
            section_name:   section["name"],
            prices_payload: Array(item["prices"]),
            addons_payload: addon_rows(item["addons"]),
            image_bbox:     item["image_bbox"],
            position:       position,
            decision:       "pending"
          )
          position += 1
        end
      end
    end

    # Deliberately narrow — a false fold silently drops a dish with no
    # recovery path, so only the unambiguous "Add …" prefix triggers. Not
    # "extra" (collides with "Extra Crispy Wings") and not a trailing "+"
    # (menus use it as a footnote marker); those rely on the prompt's own
    # classification, and a miss just stages a card a human can reject.
    def addon_line?(name)
      name.to_s.strip.match?(/\Aadd\s/i)
    end

    def addon_rows(addons)
      Array(addons).map do |addon|
        { "name" => addon["name"], "price_cents" => addon["price_cents"], "source" => "extract" }
      end
    end

    def guard_addon_row(item)
      name = item["name"].to_s.strip.sub(/\Aadd\s+/i, "").sub(/\s*\+\z/, "").strip
      first_price = Array(item["prices"]).first || {}
      { "name" => name, "price_cents" => first_price["price_cents"], "source" => "guard" }
    end
  end
end
