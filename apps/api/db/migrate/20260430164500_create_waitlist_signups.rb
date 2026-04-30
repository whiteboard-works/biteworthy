class CreateWaitlistSignups < ActiveRecord::Migration[8.1]
  # Phase 5.10 — soft-launch waitlist for the marketing landing.
  #
  # Single column doing real work: `email` (citext for case-insensitive
  # uniqueness — cIteXt@Foo.com and citext@foo.com are the same row).
  #
  # `source` lets us split conversion by referrer eventually
  # (`landing_hero`, `press_page`, etc.) without a schema change.
  #
  # `confirmed_at` left for a future double-opt-in if Postmark
  # deliverability ever requires it; for v1 every signup is
  # immediately on the list (the confirmation email is informational,
  # not a gate).
  def change
    create_table :waitlist_signups, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.citext   :email,   null: false
      t.string   :source,  null: false, default: "landing"
      t.datetime :confirmed_at
      t.timestamps
    end

    add_index :waitlist_signups, :email, unique: true
  end
end
