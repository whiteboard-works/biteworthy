# Legal remediation E10 — stores DMCA takedown notices submitted via
# /dmca, backing the ToS § Copyright clause + the §512 safe harbor
# (the designated agent gets registered separately in L2). Persisting
# each notice gives an auditable record and the data behind the
# repeat-infringer process (an admin/ops review over these rows).
class CreateDmcaNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :dmca_notices, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :complainant_name,  null: false
      t.string   :complainant_email, null: false
      t.text     :infringing_url,    null: false
      t.text     :work_description,  null: false
      # The two §512(c)(3) sworn statements, captured as checkboxes.
      t.boolean  :good_faith,        null: false, default: false
      t.boolean  :accuracy_sworn,    null: false, default: false
      t.string   :signature,         null: false
      # received | actioned | rejected — admins move it through review.
      t.string   :status,            null: false, default: "received"
      t.timestamps
    end

    add_index :dmca_notices, :status
    add_index :dmca_notices, :created_at
  end
end
