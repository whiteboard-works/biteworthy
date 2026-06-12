# Phase 6.4 — one-click graduation of a community-published
# restaurant to strict-mode visibility. Flips every human-vouched
# `suggested` association (and the items' own confidence) to
# `confirmed`. AI-sourced rows are left alone — see
# Restaurant#confirm_community_associations!.
class Avo::Actions::Restaurants::ConfirmCommunity < Avo::BaseAction
  self.name = "Confirm community menu → strict-mode visible"
  self.message = "Flip all human-verified `suggested` associations on the selected restaurant(s) to `confirmed`? Strict-mode users will start seeing these items."
  self.confirm_button_label = "Confirm all"

  def handle(query:, **)
    totals = self.class.confirm_all(query)

    succeed "Confirmed #{totals[:items]} item(s), " \
            "#{totals[:ingredients]} ingredient link(s), " \
            "#{totals[:tags]} tag link(s) across #{totals[:restaurants]} restaurant(s)."
  end

  # Pure logic; reusable by specs (mirrors IngestionItems::Accept).
  def self.confirm_all(restaurants)
    totals = { restaurants: 0, items: 0, ingredients: 0, tags: 0 }

    restaurants.each do |restaurant|
      counts = restaurant.confirm_community_associations!
      totals[:restaurants] += 1
      totals[:items]       += counts[:items]
      totals[:ingredients] += counts[:ingredients]
      totals[:tags]        += counts[:tags]
    end

    totals
  end
end
