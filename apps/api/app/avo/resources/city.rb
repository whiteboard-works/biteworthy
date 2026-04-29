class Avo::Resources::City < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :slug, as: :text
    field :name, as: :text
    field :region, as: :text
    field :country, as: :country
    field :latitude, as: :number
    field :longitude, as: :number
    field :restaurants, as: :has_many
  end
end
