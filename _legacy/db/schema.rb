# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20191104014440) do

  create_table "addresses", force: :cascade do |t|
    t.integer "restaurant_id", limit: 4
    t.string  "phone_number",  limit: 255
    t.string  "street",        limit: 255
    t.string  "city",          limit: 255,                          default: "Durango"
    t.string  "state",         limit: 255,                          default: "CO"
    t.integer "zip",           limit: 4,                            default: 81301
    t.decimal "latitude",                  precision: 10, scale: 6
    t.decimal "longitude",                 precision: 10, scale: 6
    t.string  "place_id",      limit: 255
  end

  create_table "cache_histories", primary_key: "name", force: :cascade do |t|
    t.integer  "recache_count", limit: 4, default: 0
    t.integer  "write_count",   limit: 4, default: 0
    t.datetime "expires_at"
    t.datetime "created_at",                          null: false
    t.datetime "updated_at",                          null: false
  end

  create_table "extras", force: :cascade do |t|
    t.integer  "restaurant_id", limit: 4
    t.integer  "extrable_id",   limit: 4
    t.string   "extrable_type", limit: 255
    t.integer  "addon_type",    limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "extras_tags", force: :cascade do |t|
    t.integer "extra_id", limit: 4
    t.integer "tag_id",   limit: 4
  end

  create_table "foods", force: :cascade do |t|
    t.integer  "restaurant_id", limit: 4
    t.string   "name",          limit: 255
    t.string   "description",   limit: 255
    t.integer  "user_id",       limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "food_group",    limit: 4
  end

  create_table "foods_ingredients", force: :cascade do |t|
    t.integer  "food_id",       limit: 4
    t.integer  "ingredient_id", limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "foods_tags", force: :cascade do |t|
    t.integer "food_id", limit: 4
    t.integer "tag_id",  limit: 4
  end

  create_table "foods_varieties", force: :cascade do |t|
    t.integer  "food_id",    limit: 4
    t.integer  "variety_id", limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "hours", force: :cascade do |t|
    t.time     "opens"
    t.time     "closes"
    t.integer  "day",        limit: 4
    t.integer  "hour_id",    limit: 4
    t.string   "hour_type",  limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "ingredient_hierarchies", id: false, force: :cascade do |t|
    t.integer "ancestor_id",   limit: 4, null: false
    t.integer "descendant_id", limit: 4, null: false
    t.integer "generations",   limit: 4, null: false
  end

  add_index "ingredient_hierarchies", ["ancestor_id", "descendant_id", "generations"], name: "ingredient_anc_desc_idx", unique: true, using: :btree
  add_index "ingredient_hierarchies", ["descendant_id"], name: "ingredient_desc_idx", using: :btree

  create_table "ingredients", force: :cascade do |t|
    t.string   "name",            limit: 255
    t.string   "normalized_name", limit: 255
    t.integer  "user_id",         limit: 4
    t.integer  "parent_id",       limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "ingredients_tags", force: :cascade do |t|
    t.integer "ingredient_id", limit: 4
    t.integer "tag_id",        limit: 4
  end

  create_table "items", force: :cascade do |t|
    t.integer  "restaurant_id", limit: 4
    t.string   "name",          limit: 255
    t.string   "description",   limit: 255
    t.integer  "status",        limit: 4,   default: 0
    t.boolean  "recommended"
    t.integer  "user_id",       limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "items_extras", force: :cascade do |t|
    t.integer "item_id",  limit: 4
    t.integer "extra_id", limit: 4
  end

  create_table "items_foods", force: :cascade do |t|
    t.integer "item_id", limit: 4
    t.integer "food_id", limit: 4
  end

  create_table "items_ingredients", force: :cascade do |t|
    t.integer "item_id",       limit: 4
    t.integer "ingredient_id", limit: 4
  end

  create_table "items_menu_groups", force: :cascade do |t|
    t.integer "item_id",       limit: 4
    t.integer "menu_group_id", limit: 4
  end

  add_index "items_menu_groups", ["item_id"], name: "index_items_menu_groups_on_item_id", using: :btree
  add_index "items_menu_groups", ["menu_group_id"], name: "index_items_menu_groups_on_menu_group_id", using: :btree

  create_table "items_tags", force: :cascade do |t|
    t.integer "item_id", limit: 4
    t.integer "tag_id",  limit: 4
  end

  create_table "menu_groups", force: :cascade do |t|
    t.integer  "restaurant_id", limit: 4
    t.integer  "menu_order",    limit: 4,     default: 1
    t.string   "name",          limit: 255
    t.text     "description",   limit: 65535
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "menu_groups_menus", force: :cascade do |t|
    t.integer "menu_group_id", limit: 4
    t.integer "menu_id",       limit: 4
  end

  add_index "menu_groups_menus", ["menu_group_id"], name: "index_menu_groups_menus_on_menu_group_id", using: :btree
  add_index "menu_groups_menus", ["menu_id"], name: "index_menu_groups_menus_on_menu_id", using: :btree

  create_table "menu_groups_tags", force: :cascade do |t|
    t.integer "menu_group_id", limit: 4
    t.integer "tag_id",        limit: 4
  end

  create_table "menus", force: :cascade do |t|
    t.integer  "restaurant_id", limit: 4
    t.string   "name",          limit: 255, default: "Default"
    t.string   "description",   limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "photos", force: :cascade do |t|
    t.integer  "user_id",            limit: 4
    t.integer  "photo_id",           limit: 4
    t.string   "photo_type",         limit: 255
    t.string   "image_file_name",    limit: 255
    t.string   "image_content_type", limit: 255
    t.integer  "image_file_size",    limit: 4
    t.datetime "image_updated_at"
    t.integer  "image_type",         limit: 4,   default: 1
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "points", force: :cascade do |t|
    t.integer  "user_id",        limit: 4
    t.integer  "worth",          limit: 4
    t.integer  "object_id",      limit: 4
    t.string   "object_class",   limit: 255
    t.integer  "change_type",    limit: 4
    t.text     "object_changes", limit: 65535
    t.datetime "created_at",                   null: false
    t.datetime "updated_at",                   null: false
  end

  create_table "prices", force: :cascade do |t|
    t.integer "priced_id",   limit: 4
    t.string  "priced_type", limit: 255
    t.float   "value",       limit: 24
    t.string  "size",        limit: 255
  end

  create_table "reports", force: :cascade do |t|
    t.string   "name",        limit: 255
    t.text     "description", limit: 65535
    t.string   "page_url",    limit: 255
    t.integer  "report_type", limit: 4
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
  end

  create_table "restaurants", force: :cascade do |t|
    t.string   "name",            limit: 255
    t.string   "slogan",          limit: 255
    t.string   "main_image_url",  limit: 255
    t.string   "about",           limit: 255
    t.string   "disclaimer",      limit: 255
    t.string   "website",         limit: 255
    t.integer  "inside_seating",  limit: 4
    t.integer  "outside_seating", limit: 4
    t.boolean  "cash_only"
    t.boolean  "delivers"
    t.boolean  "wifi"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "active"
  end

  create_table "restaurants_tags", force: :cascade do |t|
    t.integer "restaurant_id", limit: 4
    t.integer "tag_id",        limit: 4
  end

  create_table "restaurants_users", force: :cascade do |t|
    t.integer "restaurant_id", limit: 4
    t.integer "user_id",       limit: 4
  end

  create_table "reviews", force: :cascade do |t|
    t.integer  "rating",      limit: 4
    t.integer  "user_id",     limit: 4
    t.integer  "review_id",   limit: 4
    t.string   "review_type", limit: 255
    t.string   "title",       limit: 255
    t.text     "description", limit: 65535
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "seasons", force: :cascade do |t|
    t.string   "name",        limit: 255
    t.date     "start_date"
    t.date     "end_date"
    t.boolean  "single_day"
    t.integer  "season_id",   limit: 4
    t.string   "season_type", limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.string   "session_id", limit: 255,   null: false
    t.text     "data",       limit: 65535
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "sessions", ["session_id"], name: "index_sessions_on_session_id", unique: true, using: :btree
  add_index "sessions", ["updated_at"], name: "index_sessions_on_updated_at", using: :btree

  create_table "tag_hierarchies", id: false, force: :cascade do |t|
    t.integer "ancestor_id",   limit: 4, null: false
    t.integer "descendant_id", limit: 4, null: false
    t.integer "generations",   limit: 4, null: false
  end

  add_index "tag_hierarchies", ["ancestor_id", "descendant_id", "generations"], name: "tag_anc_desc_idx", unique: true, using: :btree
  add_index "tag_hierarchies", ["descendant_id"], name: "tag_desc_idx", using: :btree

  create_table "tag_histories", force: :cascade do |t|
    t.string   "tag_id",              limit: 255
    t.string   "name",                limit: 255
    t.integer  "created_by_id",       limit: 4
    t.integer  "last_modified_by_id", limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "tags", force: :cascade do |t|
    t.string   "name",              limit: 255
    t.string   "description",       limit: 255
    t.integer  "variety",           limit: 4
    t.integer  "user_id",           limit: 4
    t.integer  "parent_id",         limit: 4
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "icon_file_name",    limit: 255
    t.string   "icon_content_type", limit: 255
    t.integer  "icon_file_size",    limit: 4
    t.datetime "icon_updated_at"
  end

  create_table "user_roles", force: :cascade do |t|
    t.string   "key",        limit: 255
    t.string   "name",       limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "user_roles", ["key"], name: "index_user_roles_on_key", unique: true, using: :btree

  create_table "users", force: :cascade do |t|
    t.string   "user_name",              limit: 255, default: "", null: false
    t.string   "first_name",             limit: 255, default: "", null: false
    t.string   "last_name",              limit: 255, default: "", null: false
    t.string   "email",                  limit: 255, default: "", null: false
    t.string   "encrypted_password",     limit: 255, default: "", null: false
    t.boolean  "approved"
    t.boolean  "is_admin"
    t.boolean  "is_editor"
    t.boolean  "is_staff"
    t.integer  "level",                  limit: 4
    t.integer  "strikes",                limit: 4
    t.boolean  "banned"
    t.datetime "banned_at"
    t.string   "reset_password_token",   limit: 255
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          limit: 4,   default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip",     limit: 255
    t.string   "last_sign_in_ip",        limit: 255
    t.string   "confirmation_token",     limit: 255
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string   "unconfirmed_email",      limit: 255
    t.integer  "failed_attempts",        limit: 4,   default: 0,  null: false
    t.string   "unlock_token",           limit: 255
    t.datetime "locked_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "provider",               limit: 50,  default: "", null: false
    t.string   "uid",                    limit: 500, default: "", null: false
  end

  add_index "users", ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true, using: :btree
  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree
  add_index "users", ["unlock_token"], name: "index_users_on_unlock_token", unique: true, using: :btree

  create_table "users_roles", force: :cascade do |t|
    t.string   "user_id",    limit: 255
    t.string   "role_id",    limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "varieties", force: :cascade do |t|
    t.string   "name",             limit: 255
    t.integer  "ingredient_id",    limit: 4
    t.boolean  "ingredient_first",             default: false
    t.datetime "created_at",                                   null: false
    t.datetime "updated_at",                                   null: false
  end

end
