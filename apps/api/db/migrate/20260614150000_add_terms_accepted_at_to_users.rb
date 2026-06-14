# Risk-reduction follow-up — records that the user affirmatively agreed
# to the Terms of Service + Privacy Policy at signup (clickwrap). An
# explicit, recorded acceptance is what makes the ToS — including the
# arbitration clause + class-action waiver — enforceable, versus weak
# "by using the site you agree" browsewrap. Nullable: accounts created
# before the clickwrap (and OAuth accounts) have no stamp.
class AddTermsAcceptedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :terms_accepted_at, :datetime, null: true
  end
end
