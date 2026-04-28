class CreateIngestion < ActiveRecord::Migration[8.0]
  def change
    create_table :ingestion_runs, id: :uuid do |t|
      t.references :user,       type: :uuid, foreign_key: true
      t.references :restaurant, type: :uuid, foreign_key: true # null until restaurant is created
      t.string :input_kind, null: false                   # photo | url | pdf
      t.string :source_url
      t.string :status, null: false, default: "queued"    # queued | extracting | resolving | staged | published | failed
      t.string :model
      t.integer :cost_cents, default: 0
      t.jsonb :raw_output, default: {}
      t.text  :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    create_table :ingestion_items, id: :uuid do |t|
      t.references :ingestion_run, type: :uuid, null: false, foreign_key: true
      t.references :item,          type: :uuid, foreign_key: true # set on accept
      t.string :name
      t.text   :description
      t.string :section_name
      t.jsonb  :prices_payload,             default: []  # [{size, price_cents}]
      t.jsonb  :ingredients_payload,        default: []  # [{slug, confidence}]
      t.jsonb  :tags_payload,                default: []  # [{slug, confidence}]
      t.jsonb  :unresolved_ingredients,      default: [] # raw strings AI extracted that didn't match the catalog
      t.string :decision, null: false, default: "pending" # pending | accepted | rejected | edited
      t.datetime :decided_at
      t.timestamps
    end
    add_index :ingestion_items, [:ingestion_run_id, :decision]
  end
end
