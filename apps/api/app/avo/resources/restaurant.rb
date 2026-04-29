class Avo::Resources::Restaurant < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :city_id, as: :text
    field :slug, as: :text
    field :name, as: :text
    field :about, as: :textarea
    field :website, as: :text
    field :phone, as: :text
    field :status, as: :text
    field :claimed_by_user_id, as: :text
    field :claimed_at, as: :date_time
    field :city, as: :belongs_to
    field :claimed_by_user, as: :belongs_to
    field :addresses, as: :has_many
    field :hours, as: :has_many
    field :menus, as: :has_many
    field :menu_sections, as: :has_many, through: :menus
    field :items, as: :has_many
  end
end
