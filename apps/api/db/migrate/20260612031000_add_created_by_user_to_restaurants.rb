class AddCreatedByUserToRestaurants < ActiveRecord::Migration[8.1]
  # Phase 6.2 — community restaurant creation. Records which user
  # created a restaurant through POST /api/v1/restaurants so the
  # ingestion ownership rule ("non-admins may only scan drafts they
  # created, or published restaurants") and the Phase 6.4 moderation
  # scope ("community-published recently") have something to key on.
  # Nullable: admin/seed-created restaurants have no creator.
  def change
    add_reference :restaurants, :created_by_user,
                  type: :uuid, null: true,
                  foreign_key: { to_table: :users },
                  index: true
  end
end
