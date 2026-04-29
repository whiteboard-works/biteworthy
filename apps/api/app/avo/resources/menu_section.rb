class Avo::Resources::MenuSection < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :menu_id, as: :text
    field :name, as: :text
    field :description, as: :textarea
    field :position, as: :number
    field :menu, as: :belongs_to
    field :items, as: :has_many
  end
end
