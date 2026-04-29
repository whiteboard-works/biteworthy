class AddIsAdminToUsers < ActiveRecord::Migration[8.1]
  # Phase 1.5 ships an HTTP Basic gate on /admin (env-driven creds).
  # This column is set up now so Phase 4's user-tied admin sessions
  # have somewhere to look when we swap auth schemes; until then it
  # is informational only.
  def change
    add_column :users, :is_admin, :boolean, null: false, default: false
    add_index  :users, :is_admin, where: "is_admin = true"
  end
end
