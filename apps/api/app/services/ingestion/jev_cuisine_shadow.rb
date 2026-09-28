# frozen_string_literal: true

module Ingestion
  # Shadow trial of Jev (TypeSafe's System One model) against Haiku on
  # the one gap-fill decision that is a pure closed-set classification:
  # which cuisine tags a dish carries.
  #
  # For each gap-fill slice Haiku already answered, this asks Jev one
  # yes/no question per (item, cuisine tag) and logs a single
  # `[jev_shadow]` JSON line: how many pairs agree, and the pairs that
  # don't. **Nothing it computes is written.** The decision to let Jev
  # own cuisine tags is a human one, made from those log lines.
  #
  # Three deliberate choices:
  #
  #   * **One Noul per pair, not a Choice per item.** A dish can carry
  #     several cuisines (or none), and Haiku returns a set. A Choice
  #     forces exactly one, so agreement would be measured against a
  #     question Haiku was never asked.
  #
  #   * **State is only the slice's items.** Jev's accuracy drops with
  #     irrelevant state (docs.typesafe.ai "jaggedness"), so no catalog,
  #     no matched slugs — just name, description and section.
  #
  #   * **Never raises.** It runs inside a job whose failure handling
  #     means something (enrichment_status, retry_on). A trial that could
  #     trip either would be measuring itself at the product's expense.
  class JevCuisineShadow
    # A pair counts as "Jev says yes" at or above this. 0.5 is the neutral
    # read of a calibrated probability; tune it from the logs, not here.
    THRESHOLD = 0.5

    # Enough disagreements to eyeball without a slice flooding the log.
    MAX_DISAGREEMENTS_LOGGED = 20

    def self.enabled? = TypesafeClient.configured?

    def initialize(client: TypesafeClient.new)
      @client = client
    end

    # `prompt_rows` are the slice's GapFillResolveJob prompt rows, in the
    # order Haiku saw them; `haiku_result` is Haiku's parsed response.
    def call(run, prompt_rows, haiku_result)
      tags = cuisine_tags
      return if tags.empty? || prompt_rows.empty?

      started   = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      answers   = @client.system_one(state: state(prompt_rows), questions: questions(prompt_rows, tags))
      latency   = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      haiku     = haiku_sets(haiku_result, tags)

      log(run, compare(prompt_rows, tags, answers, haiku), latency)
    rescue StandardError => e
      Rails.logger.warn("[jev_shadow] IngestionRun##{run&.id} skipped: #{e.class}: #{e.message.truncate(300)}")
      nil
    end

    private

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

    # Haiku's cuisine slugs per slice index, limited to the tags Jev was
    # asked about — an unknown slug is dropped by the merge anyway.
    def haiku_sets(result, tags)
      known = tags.to_set { |t| t[:slug] }
      Array(result&.dig("items")).each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |row, sets|
        Array(row.dig("cuisine_tags", "resolved")).each do |r|
          sets[row["index"]] << r["slug"] if known.include?(r["slug"])
        end
      end
    end

    def compare(prompt_rows, tags, answers, haiku)
      stats = { pairs: 0, agree: 0, jev_only: 0, haiku_only: 0, disagreements: [] }
      prompt_rows.each_with_index do |row, i|
        tags.each do |tag|
          noul = answers.dig(key(i, tag[:slug]), "noul")
          next if noul.nil?

          jev_yes   = noul >= THRESHOLD
          haiku_yes = haiku[i].include?(tag[:slug])
          stats[:pairs] += 1
          if jev_yes == haiku_yes
            stats[:agree] += 1
          else
            stats[jev_yes ? :jev_only : :haiku_only] += 1
            stats[:disagreements] << { item: row[:name], tag: tag[:slug], jev: noul, haiku: haiku_yes }
          end
        end
      end
      stats
    end

    def log(run, stats, latency)
      stats[:disagreements] = stats[:disagreements].first(MAX_DISAGREEMENTS_LOGGED)
      Rails.logger.info("[jev_shadow] " + {
        run_id:       run.id,
        model:        @client.last_model,
        latency_ms:   latency,
        input_tokens: @client.last_usage&.dig("input_tokens"),
        **stats
      }.to_json)
    end
  end
end
