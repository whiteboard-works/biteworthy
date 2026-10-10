# frozen_string_literal: true

module Ingestion
  # Re-decides the cuisine tags on a restaurant's published dishes with
  # Jev, for menus published before Jev owned the family (Haiku's tags,
  # which the 2026-09-28 trial showed force-fitting dishes into the seven
  # leaf cuisines) and for fully matched dishes that never got one.
  #
  # What it touches: `cuisine`-family ItemTag rows only, through the join
  # table (SyncsDenormalizedIds keeps `items.tag_ids` honest). What it
  # keeps: any row a person vouched for — `source` human or owner, or
  # `confidence` confirmed, which only a person produces. What it never
  # touches: other families, and the dish's own `confidence`, which the
  # strict filter reads and which cuisine has no say in.
  #
  # All or nothing: every slice is asked before anything is written, so a
  # Jev failure part-way leaves the menu exactly as it was.
  class JevCuisineRetag
    SLICE = 20

    class Unavailable < StandardError; end

    Change = Data.define(:item, :before, :after)
    Result = Data.define(:dishes, :changes, :unchanged, :unanswered, :dry_run)

    PERSON_SOURCES = %w[human owner].freeze

    def initialize(restaurant, tagger: JevCuisineTagger.new)
      @restaurant = restaurant
      @tagger     = tagger
    end

    def call(dry_run: false)
      items   = @restaurant.items.published.includes(:menu_section, item_tags: :tag).order(:position, :name).to_a
      answers = ask(items)
      tags    = Tag.where(family: "cuisine").index_by(&:slug)

      changes    = []
      unchanged  = 0
      unanswered = 0
      Item.transaction do
        items.each do |item|
          wanted = answers[item.id]
          if wanted.nil?
            unanswered += 1
            next
          end

          before  = cuisine_rows(item)
          kept    = before.select { |row| vouched?(row) }
          after   = (kept.map { |row| row.tag.slug } + wanted.map { |w| w["slug"] }).uniq.sort
          changed = after != before.map { |row| row.tag.slug }.sort

          apply!(item, before, kept, wanted, tags) unless dry_run
          if changed
            changes << Change.new(item: item, before: before.map { |row| row.tag.slug }.sort, after: after)
          else
            unchanged += 1
          end
        end
        raise ActiveRecord::Rollback if dry_run
      end

      Result.new(dishes: items.size, changes: changes, unchanged: unchanged, unanswered: unanswered, dry_run: dry_run)
    end

    private

    # { item_id => rows } for every published dish; nil for a dish Jev did
    # not fully answer. Raises rather than returning a partial map.
    def ask(items)
      items.each_slice(SLICE).each_with_object({}) do |slice, answers|
        rows = @tagger.call(@restaurant, slice.map { |item| prompt_row(item) })
        raise Unavailable, "Jev did not answer for #{@restaurant.slug}" if rows.nil?

        slice.each_with_index { |item, i| answers[item.id] = rows[i] }
      end
    end

    def prompt_row(item)
      { name: item.name, description: item.description.presence, section: item.menu_section&.name }
    end

    def cuisine_rows(item)
      item.item_tags.select { |row| row.tag.family == "cuisine" }
    end

    def vouched?(row)
      PERSON_SOURCES.include?(row.source) || row.confidence == "confirmed"
    end

    # Machine rows Jev no longer wants go; a wanted slug updates its
    # machine row or gets a new one; a vouched row is never written to.
    def apply!(item, before, kept, wanted, tags)
      kept_slugs = kept.to_set { |row| row.tag.slug }
      machine    = (before - kept).index_by { |row| row.tag.slug }

      (machine.keys - wanted.map { |w| w["slug"] }).each { |slug| machine.fetch(slug).destroy! }
      wanted.each do |w|
        slug = w["slug"]
        next if kept_slugs.include?(slug)

        attrs = { source: "ai", confidence: ConfidenceMapper.map_confidence(w["confidence"], "ai", "suggested") }
        if (row = machine[slug])
          row.update!(**attrs)
        else
          ItemTag.create!(item: item, tag: tags.fetch(slug), **attrs)
        end
      end
    end
  end
end
