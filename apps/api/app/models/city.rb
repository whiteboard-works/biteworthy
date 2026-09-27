class City < ApplicationRecord
  has_many :restaurants, dependent: :destroy
  validates :slug, :name, presence: true
  validates :slug, uniqueness: true

  # The wire shape every city list shares: REST, admin, and the tools.
  def summary
    { id: id, slug: slug, name: name, region: region, country: country }
  end
end
