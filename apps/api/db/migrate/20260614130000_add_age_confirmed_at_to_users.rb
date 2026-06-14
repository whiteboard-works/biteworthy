# Legal remediation E4 — records that the user affirmed they are at
# least 13 at signup (COPPA; Privacy Policy + ToS state a 13+ minimum).
# We store only the affirmation timestamp — not a birth date — keeping
# the data minimal. Nullable: accounts created before the gate (and
# OAuth accounts, which rely on the provider's own age policy) have no
# stamp.
class AddAgeConfirmedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :age_confirmed_at, :datetime, null: true
  end
end
