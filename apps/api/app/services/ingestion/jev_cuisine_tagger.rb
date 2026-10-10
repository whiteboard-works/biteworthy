# frozen_string_literal: true

module Ingestion
  # Cuisine tags for gap-fill items, decided by Jev (TypeSafe's System
  # One model) rather than Haiku. One yes/no `noul` question per
  # (item, leaf cuisine tag), state limited to the slice's names,
  # descriptions and sections; a tag is kept when its probability
  # reaches THRESHOLD, and that probability is stored as the row's
  # confidence so ConfidenceMapper grades it like any other `ai` row.
  #
  # Why Jev owns this family: the 2026-09-28 shadow trial agreed with
  # Haiku on 95.6% of 1,085 (item, cuisine) pairs, and nearly every
  # disagreement was Haiku forcing a dish into a cuisine that did not
  # apply (a Venezuelan menu as Mexican, chai as Indian). A slice of ten
  # items answers in ~150ms for ~2k input tokens at $0.042/MTok, so the
  # spend is not tracked on the run.
  #
  # Three deliberate choices, carried over from the trial:
  #
  #   * **One Noul per pair, not a Choice per item.** A dish can carry
  #     several cuisines, or none.
  #
  #   * **State is only the slice's items.** Jev's accuracy drops with
  #     irrelevant state (docs.typesafe.ai "jaggedness"), so no catalog,
  #     no matched slugs — just name, description and section.
  #
  #   * **Never raises.** A failure returns nil and the slice merges
  #     without AI cuisine tags (TagDeriver's keyword pass still applies);
  #     the run completes, and a dish is merely less findable. Raising
  #     would hand the job's retry_on a reason to re-bill the Haiku call
  #     that already succeeded.
  class JevCuisineTagger
    # A pair counts as "yes" at or above this. 0.5 is the neutral read of
    # a calibrated probability, and the trial's disagreements sat on both
    # sides of it; tune it from the `[jev_cuisine]` lines, not by feel.
    THRESHOLD = 0.5

    # A 200 whose `answers` map lacks a pair, or carries something that
    # is not a probability. Reported (never raised) so a shape change on
    # TypeSafe's side shows up as an error, not as a run of dishes with
    # no cuisine.
    class PartialAnswers < StandardError; end

    def self.enabled? = TypesafeClient.configured?

    def initialize(client: TypesafeClient.new)
      @client = client
    end

    # `subject` is what the dishes belong to, for the log line: the
    # IngestionRun in gap-fill, the Restaurant in a re-tag. `prompt_rows`
    # are `{ name:, description:, section: }` hashes. Returns
    # `{ index => [{ "slug" => …, "confidence" => … }] }` with an entry for
    # every index (nil for an item Jev did not fully answer), or nil when
    # Jev could not answer at all.
    def call(subject, prompt_rows)
      tags = cuisine_tags
      return {} if tags.empty? || prompt_rows.empty?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      answers = @client.system_one(state: state(prompt_rows), questions: questions(prompt_rows, tags))
      latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      rows    = prompt_rows.each_index.to_h { |i| [ i, [] ] }
      missing = 0
      prompt_rows.each_index do |i|
        tags.each do |tag|
          noul = answers.dig(key(i, tag[:slug]), "noul")
          # An absent or malformed answer is not a "no": the item's rows
          # become nil, which the merge reads as "keep what Jev said last
          # time", and the count makes a half-answered slice visible.
          unless noul.is_a?(Numeric) && noul.between?(0, 1)
            missing += 1
            rows[i] = nil
            next
          end

          rows[i] << { "slug" => tag[:slug], "confidence" => noul } if rows[i] && noul >= THRESHOLD
        end
      end

      Rails.logger.info("[jev_cuisine] " + {
        subject:      label(subject),
        model:        @client.last_model,
        latency_ms:   latency,
        input_tokens: @client.last_usage&.dig("input_tokens"),
        items:        prompt_rows.size,
        tagged:       rows.values.sum { |r| r&.size.to_i },
        missing:      missing
      }.to_json)
      if missing.positive?
        Rails.error.report(
          PartialAnswers.new("#{missing} of #{prompt_rows.size * tags.size} answers missing or malformed"),
          handled: true, context: { subject: label(subject), model: @client.last_model }
        )
      end
      rows
    rescue StandardError => e
      Rails.logger.warn(
        "[jev_cuisine] #{label(subject)} slice gets no AI cuisine tags: #{e.class}: #{e.message.truncate(300)}"
      )
      Rails.error.report(e, handled: true, context: { subject: label(subject) })
      nil
    end

    private

    def label(subject) = "#{subject.class.name}##{subject&.id}"

    # Leaf cuisines only: the root `cuisine` node is a grouping, not a
    # label anyone would apply to a dish.
    def cuisine_tags
      @cuisine_tags ||= Tag.where(family: "cuisine").pluck(:slug, :name, :path)
                           .select { |_, _, path| path.to_s.include?(".") }
                           .map { |slug, name, _| { slug: slug, name: name } }
    end

    def state(prompt_rows)
      { items: prompt_rows.map { |r| r.slice(:name, :description, :section).compact } }
    end

    def questions(prompt_rows, tags)
      prompt_rows.each_index.each_with_object({}) do |i, h|
        tags.each do |tag|
          h[key(i, tag[:slug])] = {
            type:         "noul",
            instructions: "Is the dish `items[#{i}]` #{tag[:name]} cuisine?"
          }
        end
      end
    end

    def key(index, slug) = "i#{index}__#{slug}"
  end
end
