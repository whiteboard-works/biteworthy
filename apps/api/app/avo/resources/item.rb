class Avo::Resources::Item < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :restaurant_id, as: :text
    field :menu_section_id, as: :text
    field :name, as: :text
    field :description, as: :textarea
    field :status, as: :text
    field :confidence, as: :text
    field :popularity, as: :number
    field :ingredient_ids, as: :text
    field :tag_ids, as: :text
    field :created_by_user_id, as: :text
    field :restaurant, as: :belongs_to
    field :menu_section, as: :belongs_to
    field :created_by_user, as: :belongs_to
    field :item_variants, as: :has_many
    field :item_modifiers, as: :has_many
    field :item_ingredients, as: :has_many
    field :ingredients, as: :has_many, through: :item_ingredients
    field :reviews, as: :has_many
  end
end
