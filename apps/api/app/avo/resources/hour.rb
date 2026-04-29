class Avo::Resources::Hour < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :restaurant_id, as: :text
    field :day_of_week, as: :number
    field :opens_at, as: :date_time
    field :closes_at, as: :date_time
    field :restaurant, as: :belongs_to
  end
end
