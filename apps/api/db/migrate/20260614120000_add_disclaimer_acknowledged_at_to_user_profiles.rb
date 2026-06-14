# Legal remediation E1 — records that the user saw and accepted the
# allergen disclaimer at onboarding. Server-stamped (never a
# client-supplied time); nullable because profiles created before this
# migration, and anonymous browsing, have no acknowledgment.
class AddDisclaimerAcknowledgedAtToUserProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :user_profiles, :disclaimer_acknowledged_at, :datetime, null: true
  end
end
