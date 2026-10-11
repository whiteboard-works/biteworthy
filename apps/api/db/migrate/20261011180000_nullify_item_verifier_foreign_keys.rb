# Deleting an account is `current_user.destroy!`. The verifier keys that
# AddVerificationToItems created had no ON DELETE, so anyone who had
# verified a dish could not delete their account. The verification
# timestamp stays; only the pointer to the deleted user is cleared.
# schema.rb already recorded these keys as nullify, which is why CI,
# loading the schema rather than migrating, never saw the failure.
class NullifyItemVerifierForeignKeys < ActiveRecord::Migration[8.1]
  COLUMNS = %i[human_verified_by_user_id restaurant_verified_by_user_id].freeze

  def up
    COLUMNS.each do |column|
      remove_foreign_key :items, column: column
      add_foreign_key :items, :users, column: column, on_delete: :nullify
    end
  end

  def down
    COLUMNS.each do |column|
      remove_foreign_key :items, column: column
      add_foreign_key :items, :users, column: column
    end
  end
end
