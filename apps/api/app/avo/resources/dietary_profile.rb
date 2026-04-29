class Avo::Resources::DietaryProfile < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :slug, as: :text
    field :name, as: :text
    field :description, as: :textarea
    field :dietary_profile_ingredients, as: :has_many
    field :ingredients, as: :has_many, through: :dietary_profile_ingredients
  end
end
