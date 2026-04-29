class Avo::Resources::ItemVariant < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :item_id, as: :text
    field :size, as: :text
    field :price_cents, as: :number
    field :currency, as: :text
    field :position, as: :number
    field :item, as: :belongs_to
  end
end
