class Avo::Resources::ItemModifier < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :item_id, as: :text
    field :name, as: :text
    field :kind, as: :text
    field :price_cents, as: :number
    field :ingredient_ids, as: :text
    field :tag_ids, as: :text
    field :item, as: :belongs_to
  end
end
