# frozen_string_literal: true

module Ingestion
  # Compound sauces and spreads that sit under `condiment` in the taxonomy
  # but are made from an allergen. A dish matched to `condiment-aioli`
  # carried no egg, so an egg-avoider's path filter never hid it. Each
  # entry lists what the standard recipe contains; a house version without
  # it is a person's correction to make, and an extra row hides the dish
  # with a reason rather than showing it as safe.
  #
  # Both inference seams apply it, like DietClaims: DeterministicResolver
  # on catalog matches and GapFillResolveJob on the model's rows.
  module IngredientImplications
    module_function

    TABLE = {
      "condiment-aioli"                     => %w[egg],
      "condiment-mayonnaise"                => %w[egg],
      "condiment-dips-remoulade"            => %w[egg],
      "condiment-dips-tartar-sauce"         => %w[egg],
      "condiment-dips-comeback-sauce"       => %w[egg],
      "condiment-dressings-thousand-island" => %w[egg],
      "condiment-dressings-russian"         => %w[egg],
      "condiment-dressings-ranch"           => %w[egg dairy-buttermilk],
      "condiment-dressings-caesar"          => %w[egg fish-anchovy dairy-parmesan],
      "condiment-dressings-green-goddess"   => %w[egg fish-anchovy dairy-sour-cream],
      "condiment-sauces-hollandaise"        => %w[egg dairy-butter],
      "condiment-sauces-bearnaise"          => %w[egg dairy-butter],
      "condiment-pesto"                     => %w[dairy-parmesan tree_nut-pine-nuts],
      "condiment-worcestershire-sauce"      => %w[fish-anchovy],
      "condiment-fish-sauce"                => %w[fish-anchovy],
      "condiment-oyster-sauce"              => %w[shellfish-mollusk-oyster],
      "condiment-hoisin-sauce"              => %w[soy grain-wheat],
      "condiment-tzatziki"                  => %w[dairy-yogurt],
      "condiment-hummus"                    => %w[sesame-tahini],
      "condiment-baba-ganoush"              => %w[sesame-tahini],
      "condiment-sauces-romesco"            => %w[tree_nut-almond],
      "condiment-spreads-muhammara"         => %w[tree_nut-walnut]
    }.freeze

    # [slug, path] pairs implied by `slugs`, minus any a name's diet
    # claim rules out. `path_for` maps a slug to its ltree path (nil when
    # the catalog lacks it).
    def implied(slugs, path_for:, claims:)
      slugs.flat_map { |slug| TABLE.fetch(slug, []) }.uniq.filter_map do |slug|
        path = path_for.call(slug)&.to_s
        next if path.blank? || vetoed?(claims, slug, path)

        [ slug, path ]
      end
    end

    # DietClaims only knows gluten-, dairy-, and nut-free; a "Vegan Pesto"
    # must not gain parmesan from its name either.
    def vetoed?(claims, slug, path)
      diet = TagDeriver::Diet
      return true if claims.include?("vegan") &&
                     TagDeriver.under_any?(path, diet::ANIMAL_PREFIXES + diet::VEGAN_ONLY_PREFIXES)
      return true if claims.include?("vegetarian") && TagDeriver.under_any?(path, diet::ANIMAL_PREFIXES)

      DietClaims.contradicted?(claims, slug: slug, path: path)
    end
  end
end
