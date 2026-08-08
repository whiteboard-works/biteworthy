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

      out = timed_anthropic_call(@run, api_error: "anthropic_api_error",
                                       validation_error: "schema_validation_failed") do |client|
        client.messages_create(
          system:          ExtractMenuPrompt.system(client),
          messages:        ExtractMenuPrompt.user_messages(client, blobs),
          response_schema: MenuExtractionSchema
        )
      end
      return if out.nil?

      result, elapsed_ms = out

      # Materialize the dishes NOW, with empty ingredient/tag payloads, so a
      # caller sees real items seconds after extraction; ResolveRun enriches
      # them in place. Atomic with the transition so a run never sits in
      # :resolving without its items.
      @run.transaction do
        @run.update!(staging: result, latency_ms: elapsed_ms)
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
