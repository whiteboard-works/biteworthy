# Seed the canonical taxonomy (ingredients + tags + dietary profiles).
# Idempotent: re-running upserts and never destroys.
#
# Real ingredient data is loaded from db/seeds/ingredients.yml. The 2020
# code had a giant Ruby module with ~1500 ingredients hand-curated; that
# list is being ported forward into structured YAML so it can be diffed
# and reviewed.

require "yaml"

def seed_yaml(filename)
  path = Rails.root.join("db/seeds", filename)
  return [] unless File.exist?(path)
  YAML.load_file(path)
end

puts "== Tags =="
seed_yaml("tags.yml").each do |row|
  tag = Tag.find_or_initialize_by(slug: row["slug"])
  tag.assign_attributes(row)
  tag.save!
end
puts "  #{Tag.count} tags"

puts "== Ingredients =="
seed_yaml("ingredients.yml").each do |row|
  ing = Ingredient.find_or_initialize_by(slug: row["slug"])
  ing.assign_attributes(row)
  ing.save!
end
puts "  #{Ingredient.count} ingredients"

# Resolve a list of ltree path roots (e.g. ["dairy", "meat"]) into the
# ids of every Ingredient/Tag in those subtrees. Uses the GiST index on
# `path` (same one Phase 1.7's filter query hits).
def ids_under_paths(scope, paths)
  return [] if Array(paths).empty?
  scope.where("path <@ ARRAY[?]::ltree[]", Array(paths)).pluck(:id)
end

puts "== Dietary profiles =="
seed_yaml("dietary_profiles.yml").each do |row|
  ingredient_slugs = row.delete("avoid_ingredient_slugs") || []
  ingredient_paths = row.delete("avoid_ingredient_paths") || []
  tag_slugs        = row.delete("avoid_tag_slugs")        || []
  tag_paths        = row.delete("avoid_tag_paths")        || []

  profile = DietaryProfile.find_or_initialize_by(slug: row["slug"])
  profile.assign_attributes(row)
  profile.save!

  # Union slug-matched + path-matched ids before linking. Idempotent
  # because the join row uniqueness index dedupes.
  ingredient_ids = (
    Ingredient.where(slug: ingredient_slugs).pluck(:id) +
    ids_under_paths(Ingredient, ingredient_paths)
  ).uniq

  tag_ids = (
    Tag.where(slug: tag_slugs).pluck(:id) +
    ids_under_paths(Tag, tag_paths)
  ).uniq

  Ingredient.where(id: ingredient_ids).find_each do |ing|
    DietaryProfileIngredient.find_or_create_by!(
      dietary_profile: profile, ingredient: ing, rule: "avoid"
    )
  end

  Tag.where(id: tag_ids).find_each do |tag|
    DietaryProfileTag.find_or_create_by!(
      dietary_profile: profile, tag: tag, rule: "avoid"
    )
  end
end
puts "  #{DietaryProfile.count} dietary profiles"
