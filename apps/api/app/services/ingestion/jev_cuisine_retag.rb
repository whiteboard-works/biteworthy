# frozen_string_literal: true

module Ingestion
  # Re-decides the cuisine tags on a restaurant's published dishes with
  # Jev, for menus published before Jev owned the family (Haiku's tags,
  # which the 2026-09-28 trial showed force-fitting dishes into the seven
  # leaf cuisines) and for fully matched dishes that never got one.
  #
  # What it manages: `cuisine`-family ItemTag rows with `source: "ai"` —
  # the rows a model wrote, Haiku's then and Jev's now — through the join
  # table, so `items.tag_ids` stays honest. Every other cuisine row stays
  # exactly as it is: a person's (`human`, `owner`, or `confirmed`), and
  # TagDeriver's keyword hits (`derived`, `match`), which gap-fill also
  # keeps beside Jev's answers. Other families and the dish's own
  # `confidence` (what the strict filter reads) are never touched.
  #
  # All or nothing: every slice is asked before anything is written, so a
  # Jev failure part-way leaves the menu exactly as it was. Each dish is
  # locked and its rows re-read inside the transaction, and one whose
  # text or section changed since it was sent to Jev is skipped, so an
  # edit made while Jev was answering is neither overwritten nor collided
  # with.
  class JevCuisineRetag
    # Same as gap-fill's slice. Every item is now a gate plus one Noul
    # per leaf cuisine, each with criteria, so twenty dishes would be
    # ~480 questions in one request.
    SLICE = 10

    class Unavailable < StandardError; end

    # `before` / `after` are the dish's cuisine rows as { slug:, confidence: }.
    # `regrade` is true when the slugs are the same and only a grade moved,
    # so a report can tell a real re-tag from confidence churn.
    Change = Data.define(:item, :before, :after, :regrade)
    # `stale` counts dishes edited while Jev was answering — text or
    # section (the answer was about the old text), or anything else on
    # the row, tags and status included (the timestamp moves); they are
    # left alone.
    Result = Data.define(:dishes, :changes, :unchanged, :unanswered, :stale, :dry_run)

    MANAGED_SOURCE = "ai"

    def initialize(restaurant, tagger: JevCuisineTagger.new)
      @restaurant = restaurant
      @tagger     = tagger
    end

    def call(dry_run: false)
      tags = leaf_cuisine_tags
      raise Unavailable, "the taxonomy has no leaf cuisine tags" if tags.empty?

      items   = @restaurant.items.published.includes(:menu_section).order(:position, :name).to_a
      asked   = items.to_h { |item| [ item.id, [ item.updated_at, prompt_row(item) ] ] }
      answers = ask(items)

      changes    = []
      unchanged  = 0
      unanswered = 0
      stale      = 0
      Item.transaction do
        Item.defer_denormalization do
          items.each do |item|
            wanted = answers[item.id]
            if wanted.nil?
              unanswered += 1
              next
            end

            item.lock!
            # lock! re-reads the dish, so the timestamp catches any edit to
            # the row, its tags (denormalization touches it) or its status;
            # the section is re-read by hand because a rename or removal
            # goes through the section row and leaves the dish untouched.
            item.association(:menu_section).reset
            if [ item.updated_at, prompt_row(item) ] != asked.fetch(item.id)
              stale += 1
              next
            end

            current = item.item_tags.includes(:tag).reload.select { |row| row.tag.family == "cuisine" }
            managed = current.select { |row| row.source == MANAGED_SOURCE }
            kept    = current - managed
            target  = wanted.reject { |w| kept.any? { |row| row.tag.slug == w["slug"] } }
                            .to_h { |w| [ w["slug"], ConfidenceMapper.map_confidence(w["confidence"], "ai", "suggested") ] }

            if managed.to_h { |row| [ row.tag.slug, row.confidence ] } == target
              unchanged += 1
              next
            end

            # Snapshot before apply!, which updates these very rows.
            before = rows(current.map { |row| [ row.tag.slug, row.confidence ] })
            after  = rows(kept.map { |row| [ row.tag.slug, row.confidence ] } + target.to_a)
            apply!(item, managed, target, tags) unless dry_run
            # From what apply! does, not from the display rows: the same
            # managed slugs with a grade moved is a regrade, nothing else is.
            regrade = managed.map { |row| row.tag.slug }.sort == target.keys.sort
            changes << Change.new(item: item, before: before, after: after, regrade: regrade)
          end
        end
        raise ActiveRecord::Rollback if dry_run
      end

      Result.new(dishes: items.size, changes: changes, unchanged: unchanged, unanswered: unanswered,
                 stale: stale, dry_run: dry_run)
    end

    private

    def leaf_cuisine_tags
      Tag.where(family: "cuisine").select { |tag| tag.path.to_s.include?(".") }.index_by(&:slug)
    end

    # { item_id => rows } for every published dish; nil for a dish Jev did
    # not fully answer. Raises rather than returning a partial map, and
    # on the first failed slice, so an outage costs one timeout.
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

    def rows(pairs)
      pairs.sort_by(&:first).map { |slug, confidence| { slug: slug, confidence: confidence } }
    end

    # Managed rows Jev no longer wants go; a wanted slug updates its
    # managed row when the grade moved, or gets a new one.
    def apply!(item, managed, target, tags)
      by_slug = managed.index_by { |row| row.tag.slug }
      (by_slug.keys - target.keys).each { |slug| by_slug.fetch(slug).destroy! }
      target.each do |slug, confidence|
        if (row = by_slug[slug])
          row.update!(confidence: confidence) if row.confidence != confidence
        else
          ItemTag.create!(item: item, tag: tags.fetch(slug), source: MANAGED_SOURCE, confidence: confidence)
        end
      end
    end
  end
end
