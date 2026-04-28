class City < ApplicationRecord
  has_many :restaurants, dependent: :destroy
  validates :slug, :name, presence: true
  validates :slug, uniqueness: true
end
