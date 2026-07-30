class AddAddonsPayloadToIngestionItems < ActiveRecord::Migration[8.1]
  # Add-on/upsell lines ("Add guajillo-tomatillo salsa + $4.00") nested under
  # their parent dish at extraction. Rows: { name, price_cents, source }
  # where source is "extract" (LLM classified it) or "guard" (deterministic
  # materialization backstop folded a stray top-level "Add X" item).
  # Promoted to ItemModifier (kind: "addition") when the parent is accepted.
  def change
    add_column :ingestion_items, :addons_payload, :jsonb, default: [], null: false
  end
end
