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

puts "== Dietary profiles =="
seed_yaml("dietary_profiles.yml").each do |row|
  ingredient_slugs = row.delete("avoid_ingredient_slugs") || []
  tag_slugs        = row.delete("avoid_tag_slugs")        || []

  profile = DietaryProfile.find_or_initialize_by(slug: row["slug"])
  profile.assign_attributes(row)
  profile.save!

  Ingredient.where(slug: ingredient_slugs).find_each do |ing|
    DietaryProfileIngredient.find_or_create_by!(
      dietary_profile: profile,
      ingredient: ing,
      rule: "avoid",
    )
  end

  Tag.where(slug: tag_slugs).find_each do |tag|
    DietaryProfileTag.find_or_create_by!(
      dietary_profile: profile,
      tag: tag,
      rule: "avoid",
    )
  end
end
puts "  #{DietaryProfile.count} dietary profiles"
