# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_29_194420) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "ltree"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"

  create_table "addresses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "city"
    t.string "country", default: "US"
    t.datetime "created_at", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "map_provider_place_id"
    t.string "postal_code"
    t.string "region"
    t.uuid "restaurant_id", null: false
    t.string "street"
    t.datetime "updated_at", null: false
    t.index ["restaurant_id"], name: "index_addresses_on_restaurant_id"
  end

  create_table "cities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "country", default: "US", null: false
    t.datetime "created_at", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name", null: false
    t.string "region"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_cities_on_slug", unique: true
  end

  create_table "dietary_profile_ingredients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "dietary_profile_id", null: false
    t.uuid "ingredient_id", null: false
    t.string "rule", default: "avoid", null: false
    t.index ["dietary_profile_id", "ingredient_id"], name: "idx_dpi_unique", unique: true
    t.index ["dietary_profile_id"], name: "index_dietary_profile_ingredients_on_dietary_profile_id"
    t.index ["ingredient_id"], name: "index_dietary_profile_ingredients_on_ingredient_id"
  end

  create_table "dietary_profile_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "dietary_profile_id", null: false
    t.string "rule", default: "avoid", null: false
    t.uuid "tag_id", null: false
    t.index ["dietary_profile_id", "tag_id"], name: "idx_dpt_unique", unique: true
    t.index ["dietary_profile_id"], name: "index_dietary_profile_tags_on_dietary_profile_id"
    t.index ["tag_id"], name: "index_dietary_profile_tags_on_tag_id"
  end

  create_table "dietary_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_dietary_profiles_on_slug", unique: true
  end

  create_table "hours", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.time "closes_at"
    t.datetime "created_at", null: false
    t.integer "day_of_week", null: false
    t.time "opens_at"
    t.uuid "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id", "day_of_week"], name: "index_hours_on_restaurant_id_and_day_of_week"
    t.index ["restaurant_id"], name: "index_hours_on_restaurant_id"
  end

  create_table "ingestion_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.string "decision", default: "pending", null: false
    t.text "description"
    t.uuid "ingestion_run_id", null: false
    t.jsonb "ingredients_payload", default: []
    t.uuid "item_id"
    t.string "name"
    t.jsonb "prices_payload", default: []
    t.string "section_name"
    t.jsonb "tags_payload", default: []
    t.jsonb "unresolved_ingredients", default: []
    t.datetime "updated_at", null: false
    t.index ["ingestion_run_id", "decision"], name: "index_ingestion_items_on_ingestion_run_id_and_decision"
    t.index ["ingestion_run_id"], name: "index_ingestion_items_on_ingestion_run_id"
    t.index ["item_id"], name: "index_ingestion_items_on_item_id"
  end

  create_table "ingestion_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "cost_cents", default: 0
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.string "input_kind", null: false
    t.string "model"
    t.jsonb "raw_output", default: {}
    t.uuid "restaurant_id"
    t.string "source_url"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["restaurant_id"], name: "index_ingestion_runs_on_restaurant_id"
    t.index ["user_id"], name: "index_ingestion_runs_on_user_id"
  end

  create_table "ingredients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "aliases", default: [], null: false, array: true
    t.boolean "allergen", default: false, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.ltree "path", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["aliases"], name: "index_ingredients_on_aliases", using: :gin
    t.index ["name"], name: "index_ingredients_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["path"], name: "index_ingredients_on_path", using: :gist
    t.index ["slug"], name: "index_ingredients_on_slug", unique: true
  end

  create_table "item_ingredients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "confidence", default: "suggested", null: false
    t.datetime "created_at", null: false
    t.uuid "ingredient_id", null: false
    t.uuid "item_id", null: false
    t.string "source", default: "human", null: false
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_item_ingredients_on_ingredient_id"
    t.index ["item_id", "ingredient_id"], name: "index_item_ingredients_on_item_id_and_ingredient_id", unique: true
    t.index ["item_id"], name: "index_item_ingredients_on_item_id"
  end

  create_table "item_modifiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "ingredient_ids", default: [], null: false, array: true
    t.uuid "item_id", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.integer "price_cents"
    t.uuid "tag_ids", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["ingredient_ids"], name: "index_item_modifiers_on_ingredient_ids", using: :gin
    t.index ["item_id"], name: "index_item_modifiers_on_item_id"
    t.index ["tag_ids"], name: "index_item_modifiers_on_tag_ids", using: :gin
  end

  create_table "item_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "confidence", default: "suggested", null: false
    t.datetime "created_at", null: false
    t.uuid "item_id", null: false
    t.string "source", default: "human", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id", "tag_id"], name: "index_item_tags_on_item_id_and_tag_id", unique: true
    t.index ["item_id"], name: "index_item_tags_on_item_id"
    t.index ["tag_id"], name: "index_item_tags_on_tag_id"
  end

  create_table "item_variants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.uuid "item_id", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents"
    t.string "size"
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_item_variants_on_item_id"
  end

  create_table "items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "confidence", default: "suggested", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_user_id"
    t.text "description"
    t.uuid "ingredient_ids", default: [], null: false, array: true
    t.uuid "menu_section_id"
    t.string "name", null: false
    t.integer "popularity", default: 0, null: false
    t.uuid "restaurant_id", null: false
    t.string "status", default: "draft", null: false
    t.uuid "tag_ids", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_items_on_created_by_user_id"
    t.index ["ingredient_ids"], name: "index_items_on_ingredient_ids", using: :gin
    t.index ["menu_section_id"], name: "index_items_on_menu_section_id"
    t.index ["name"], name: "index_items_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["restaurant_id", "status"], name: "index_items_on_restaurant_id_and_status"
    t.index ["restaurant_id"], name: "index_items_on_restaurant_id"
    t.index ["tag_ids"], name: "index_items_on_tag_ids", using: :gin
  end

  create_table "menu_sections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.uuid "menu_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["menu_id"], name: "index_menu_sections_on_menu_id"
  end

  create_table "menus", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", default: "Main", null: false
    t.integer "position", default: 0, null: false
    t.uuid "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id"], name: "index_menus_on_restaurant_id"
  end

  create_table "restaurants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "about"
    t.uuid "city_id", null: false
    t.datetime "claimed_at"
    t.uuid "claimed_by_user_id"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "phone"
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["city_id", "status"], name: "index_restaurants_on_city_id_and_status"
    t.index ["city_id"], name: "index_restaurants_on_city_id"
    t.index ["claimed_by_user_id"], name: "index_restaurants_on_claimed_by_user_id"
    t.index ["slug"], name: "index_restaurants_on_slug", unique: true
  end

  create_table "reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.uuid "item_id", null: false
    t.integer "rating", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["item_id"], name: "index_reviews_on_item_id"
    t.index ["user_id", "item_id"], name: "index_reviews_on_user_id_and_item_id", unique: true
    t.index ["user_id"], name: "index_reviews_on_user_id"
    t.check_constraint "rating >= 1 AND rating <= 5", name: "reviews_rating_range"
  end

  create_table "suggestions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "resolved_at"
    t.uuid "resolved_by_user_id"
    t.string "status", default: "pending", null: false
    t.uuid "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["resolved_by_user_id"], name: "index_suggestions_on_resolved_by_user_id"
    t.index ["status"], name: "index_suggestions_on_status"
    t.index ["subject_type", "subject_id"], name: "index_suggestions_on_subject"
    t.index ["subject_type", "subject_id"], name: "index_suggestions_on_subject_type_and_subject_id"
    t.index ["user_id"], name: "index_suggestions_on_user_id"
  end

  create_table "tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "family", null: false
    t.string "name", null: false
    t.ltree "path", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_tags_on_family"
    t.index ["path"], name: "index_tags_on_path", using: :gist
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  create_table "user_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "avoid_ingredient_ids", default: [], null: false, array: true
    t.uuid "avoid_tag_ids", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.uuid "prefer_tag_ids", default: [], null: false, array: true
    t.uuid "primary_dietary_profile_id"
    t.string "strictness", default: "balanced", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["avoid_ingredient_ids"], name: "index_user_profiles_on_avoid_ingredient_ids", using: :gin
    t.index ["avoid_tag_ids"], name: "index_user_profiles_on_avoid_tag_ids", using: :gin
    t.index ["prefer_tag_ids"], name: "index_user_profiles_on_prefer_tag_ids", using: :gin
    t.index ["primary_dietary_profile_id"], name: "index_user_profiles_on_primary_dietary_profile_id"
    t.index ["user_id"], name: "index_user_profiles_on_user_id", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "display_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "handle", null: false
    t.boolean "is_admin", default: false, null: false
    t.string "jti", null: false
    t.datetime "jti_expires_at"
    t.datetime "last_sign_in_at"
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "uid"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["handle"], name: "index_users_on_handle", unique: true
    t.index ["is_admin"], name: "index_users_on_is_admin", where: "(is_admin = true)"
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "addresses", "restaurants"
  add_foreign_key "dietary_profile_ingredients", "dietary_profiles"
  add_foreign_key "dietary_profile_ingredients", "ingredients"
  add_foreign_key "dietary_profile_tags", "dietary_profiles"
  add_foreign_key "dietary_profile_tags", "tags"
  add_foreign_key "hours", "restaurants"
  add_foreign_key "ingestion_items", "ingestion_runs"
  add_foreign_key "ingestion_items", "items"
  add_foreign_key "ingestion_runs", "restaurants"
  add_foreign_key "ingestion_runs", "users"
  add_foreign_key "item_ingredients", "ingredients"
  add_foreign_key "item_ingredients", "items"
  add_foreign_key "item_modifiers", "items"
  add_foreign_key "item_tags", "items"
  add_foreign_key "item_tags", "tags"
  add_foreign_key "item_variants", "items"
  add_foreign_key "items", "menu_sections"
  add_foreign_key "items", "restaurants"
  add_foreign_key "items", "users", column: "created_by_user_id"
  add_foreign_key "menu_sections", "menus"
  add_foreign_key "menus", "restaurants"
  add_foreign_key "restaurants", "cities"
  add_foreign_key "restaurants", "users", column: "claimed_by_user_id"
  add_foreign_key "reviews", "items"
  add_foreign_key "reviews", "users"
  add_foreign_key "suggestions", "users"
  add_foreign_key "suggestions", "users", column: "resolved_by_user_id"
  add_foreign_key "user_profiles", "dietary_profiles", column: "primary_dietary_profile_id"
  add_foreign_key "user_profiles", "users"
end
