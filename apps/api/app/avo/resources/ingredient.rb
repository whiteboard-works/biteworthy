class Avo::Resources::Ingredient < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :slug, as: :text
    field :name, as: :text
    field :path, as: :text
    field :aliases, as: :textarea
    field :allergen, as: :boolean
    field :item_ingredients, as: :has_many
    field :items, as: :has_many, through: :item_ingredients
  end
end
