class Avo::Resources::Address < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :restaurant_id, as: :text
    field :street, as: :text
    field :city, as: :text
    field :region, as: :text
    field :postal_code, as: :text
    field :country, as: :country
    field :latitude, as: :number
    field :longitude, as: :number
    field :map_provider_place_id, as: :text
    field :restaurant, as: :belongs_to
  end
end
