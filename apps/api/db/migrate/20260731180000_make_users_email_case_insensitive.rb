class MakeUsersEmailCaseInsensitive < ActiveRecord::Migration[8.1]
  # `users.email` was a plain `string` under a case-SENSITIVE unique
  # index, so `Foo@x.com` and `foo@x.com` could both exist as separate
  # accounts. Devise's `case_insensitive_keys` downcases on the Devise
  # paths, but `User.from_omniauth`, admin creates, and seeds all write
  # the address straight through — an OAuth provider returning a
  # capitalised address was one login away from a duplicate account.
  #
  # citext because `waitlist_signups.email` already uses it: same kind
  # of column, same guarantee, one convention. The extension is enabled
  # in the initial migration. Altering the type rebuilds the unique
  # index, which is what actually closes the hole.
  #
  # Safe to run: a pre-merge audit confirmed production holds no
  # `lower(email)` collisions, so the index rebuild cannot fail.
  def up
    change_column :users, :email, :citext, null: false, default: ""
  end

  def down
    change_column :users, :email, :string, null: false, default: ""
  end
end
