class Avo::Resources::Tag < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :slug, as: :text
    field :name, as: :text
    field :family, as: :text
    field :path, as: :text
    field :description, as: :textarea
    field :items, as: :has_many, through: :item_tags
  end
end
