class Avo::Actions::IngestionItems::Accept < Avo::BaseAction
  self.name = "Accept → promote to live menu"
  self.message = "Materialize a real Item + ItemIngredient + ItemTag rows for the selected ingestion item(s)? confidence: confirmed, source: human."
  self.confirm_button_label = "Accept"

  def handle(query:, **)
    promoted, updated, skipped = self.class.accept_all(query)

    msg = +"Promoted #{promoted} item(s) to live menu."
    msg << " Updated #{updated} existing item(s)." if updated.positive?
    msg << " Skipped #{skipped} already-promoted." if skipped.positive?
    succeed msg
  end

  # Pure logic; reusable by specs and by other call sites that don't
  # come through Avo's controller lifecycle (which wires up #succeed).
  def self.accept_all(items)
    promoted = 0
    updated  = 0
    skipped  = 0

    items.each do |ingestion_item|
      if ingestion_item.accepted? && ingestion_item.item.present?
        skipped += 1
        next
      end

      ingestion_item.promote!
      # An update-accept links the matched Item instead of creating one.
      if ingestion_item.item_id == ingestion_item.matched_item_id && ingestion_item.item_id.present?
        updated += 1
      else
        promoted += 1
      end
    end

    # Phase 2.5 acceptance criterion: ≥80% of decided items accepted
    # → run flips to :published, restaurant flips to :published if not
    # already.
    items.map(&:ingestion_run).uniq.each(&:maybe_publish!)

    [promoted, updated, skipped]
  end
end
