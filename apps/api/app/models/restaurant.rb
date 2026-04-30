class Restaurant < ApplicationRecord
  STATUSES = %w[draft published closed].freeze

  belongs_to :city
  belongs_to :claimed_by_user, class_name: "User", optional: true

  has_many :addresses,     dependent: :destroy
  has_many :hours,         dependent: :destroy
  has_many :menus,         dependent: :destroy
  has_many :menu_sections, through: :menus
  has_many :items,         dependent: :destroy

  validates :slug, :name, presence: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :published, -> { where(status: "published") }

  # SEO-friendly URLs (`/restaurants/ninis-1`) need lookup-by-slug;
  # mobile/api consumers still pass UUIDs. Single endpoint accepts
  # either by sniffing the value.
  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def self.find_by_id_or_slug!(value)
    if value.to_s.match?(UUID_FORMAT)
      find(value)
    else
      find_by!(slug: value)
    end
  end
end
