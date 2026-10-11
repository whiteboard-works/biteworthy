# frozen_string_literal: true

module Ingestion
  # Shadow trial: a second opinion on the wheat nobody wrote down.
  #
  # The resolver's `gap?` and Haiku's gap-fill prompt both exist to catch
  # the crust, bun, batter, breading or roux a menu never states — the
  # false negative a gluten-free filter cannot afford. This asks Jev one
  # yes/no per gap dish, "is this typically made with wheat", and compares
  # it with what the merged ingredients actually say. **Nothing it
  # computes is written to a dish.** It writes a `JevObservation` per
  # slice and logs a line; the decision whether Jev's "yes, and Haiku
  # missed it" should add a cautionary row is a human one, made from
  # those rows.
  #
  # The dangerous disagreement is `jev_only`: Jev says wheat, the data
  # says none. `data_only` is the mild one, and often right (a dish whose
  # bun is listed but which Jev reads as a salad).
  #
  # Never raises, same as JevCuisineTagger: it runs inside a job whose
  # failure handling means something. Switched by JEV_WHEAT_SHADOW so the
  # trial can be stopped without a deploy; off when the key is unset.
  class JevHiddenWheatShadow
    THRESHOLD    = 0.5
    WHEAT_PREFIX = "grain.wheat"
    MAX_DISAGREEMENTS_LOGGED = 20

    def self.enabled? = TypesafeClient.configured? && ENV["JEV_WHEAT_SHADOW"].present?

    def initialize(client: TypesafeClient.new)
      @client = client
    end

    # `prompt_rows` are the slice's gap-fill prompt rows; `merged` is
    # `{ index => merged ingredient rows }` as the job just wrote them (an
    # index the merge skipped is absent, and is counted as skipped here
    # rather than read as "no wheat"); `ingredient_paths` maps slug to
    # ltree path. Returns true when Jev answered, false when it did not,
    # so the caller can stop asking for the rest of the run.
    def call(run, prompt_rows, merged, ingredient_paths, attempt: 1)
      return true if prompt_rows.empty?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      answers = @client.system_one(state: state(prompt_rows), questions: questions(prompt_rows))
      latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      stats = compare(prompt_rows, answers, merged, ingredient_paths)
      Rails.logger.info("[jev_wheat_shadow] " + { run_id: run.id, model: @client.last_model, latency_ms: latency,
                                                   attempt: attempt, **stats }.to_json)
      JevObservation.note(
        kind: "hidden_wheat_shadow", subject: run, model: @client.last_model,
        latency_ms: latency, input_tokens: @client.last_usage&.dig("input_tokens"),
        outcome: stats[:missing].positive? ? "partial" : "answered",
        # Agreement is only a fact about pairs that were compared: a slice
        # with answers missing or nothing to compare says nothing.
        agree: agreement(stats),
        details: { attempt: attempt, **stats }
      )
      true
    rescue StandardError => e
      Rails.logger.warn("[jev_wheat_shadow] IngestionRun##{run&.id} skipped: #{e.class}: #{e.message.truncate(300)}")
      JevObservation.note(kind: "hidden_wheat_shadow", subject: run, outcome: "failed",
                          model: @client.last_model, input_tokens: @client.last_usage&.dig("input_tokens"),
                          latency_ms: started && ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
                          details: { attempt: attempt, items: Array(prompt_rows).size, error: e.class.name,
                                     status: (e.respond_to?(:status) ? e.status : nil) }.compact)
      false
    end

    private

    def state(prompt_rows)
      { items: prompt_rows.map { |r| r.slice(:name, :description, :section).compact } }
    end

    def questions(prompt_rows)
      prompt_rows.each_index.to_h do |i|
        [ key(i), {
          type:         "noul",
          instructions: "Is `items[#{i}]`, as usually prepared, made with wheat somewhere?",
          criteria:     {
            true:  { what:     "The usual preparation contains wheat even though the menu does not say so: " \
                               "a crust, bun, flour tortilla, batter, breading, pasta or noodles, pastry, " \
                               "roux, flour-thickened gravy or soy sauce",
                     examples: [ "margherita pizza", "fish and chips", "chicken parmesan", "beef stroganoff",
                                 "samosa", "country gravy", "chile relleno", "teriyaki chicken" ] },
            false: { what:     "No wheat in the usual preparation, or the menu names a wheat-free version " \
                               "(corn tortilla, rice noodles, gluten-free crust)",
                     examples: [ "grilled salmon with rice", "carne asada taco on corn tortilla", "pho", "a side salad" ] }
          }
        } ]
      end
    end

    def key(index) = "i#{index}__wheat"

    def agreement(stats)
      return nil if stats[:missing].positive? || (stats[:agree] + stats[:jev_only] + stats[:data_only]).zero?

      stats[:jev_only].zero? && stats[:data_only].zero?
    end

    def compare(prompt_rows, answers, merged, ingredient_paths)
      stats = { items: prompt_rows.size, agree: 0, jev_only: 0, data_only: 0, missing: 0, skipped: 0,
                disagreements: [] }
      prompt_rows.each_with_index do |row, i|
        unless merged.key?(i)
          stats[:skipped] += 1
          next
        end

        noul = answers.dig(key(i), "noul")
        unless noul.is_a?(Numeric) && noul.between?(0, 1)
          stats[:missing] += 1
          next
        end

        jev_yes  = noul >= THRESHOLD
        data_yes = Array(merged[i]).any? { |r| ingredient_paths[r["slug"]].to_s.start_with?(WHEAT_PREFIX) }
        if jev_yes == data_yes
          stats[:agree] += 1
        else
          stats[jev_yes ? :jev_only : :data_only] += 1
          if stats[:disagreements].size < MAX_DISAGREEMENTS_LOGGED
            stats[:disagreements] << { index: i, item: row[:name], section: row[:section], jev: noul, data: data_yes }
          end
        end
      end
      stats
    end
  end
end
