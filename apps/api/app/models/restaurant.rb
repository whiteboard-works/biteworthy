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
end
