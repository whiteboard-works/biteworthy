class EnableExtensions < ActiveRecord::Migration[8.0]
  # ltree:    hierarchical paths for ingredients and tags
  # pg_trgm:  fuzzy match for ingredient aliasing and item dedup
  # pgcrypto: gen_random_uuid()
  # citext:   case-insensitive emails and slugs
  def change
    enable_extension "pgcrypto"
    enable_extension "ltree"
    enable_extension "pg_trgm"
    enable_extension "citext"
  end
end
