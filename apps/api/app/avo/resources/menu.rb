class Avo::Resources::Menu < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :restaurant_id, as: :text
    field :name, as: :text
    field :description, as: :textarea
    field :position, as: :number
    field :restaurant, as: :belongs_to
    field :menu_sections, as: :has_many
  end
end
