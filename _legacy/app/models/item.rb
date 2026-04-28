require 'elasticsearch/model'
class Item < ActiveRecord::Base
  extend Pagy::Search
  include TrackPoints
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks
  # include CacheInvalidator
  # after_create :invalidate_cache
  # after_update :invalidate_cache
  belongs_to :restaurant
  belongs_to :user

  has_many :prices, as: :priced
  has_many :reviews, as: :review
  has_many :photos, as: :photo

  has_and_belongs_to_many :menu_groups

  has_many :foods, through: :items_foods
  has_many :items_foods

  has_many :extras, through: :items_extras
  has_many :items_extras

  # has_many :ingredients, through: :items_ingredients
  # has_many :items_ingredients

  has_many :tags, through: :items_tags
  has_many :items_tags

  accepts_nested_attributes_for :foods, reject_if: lambda { |a| a[:name].blank? }, allow_destroy: true

  validates :restaurant_id, :name, presence: true

  validates_uniqueness_of :name, scope: [:restaurant_id, :description]
  enum status: { removed: -1, draft: 0, active: 1 }

  scope :active, -> { where(status: Item.statuses[:active]) }
  scope :inactive, -> { where.not(status: Item.statuses[:active]) }
  scope :items_created, ->(user) { where(user: user).count }

  index_name "#{Rails.env}-items".downcase
  settings index: { number_of_shards: 1 } do
    mappings dynamic: 'false' do
      indexes :id, type: :integer
      indexes :restaurant_id, type: :integer
      indexes :name, analyzer: :snowball
      indexes :description, analyzer: :snowball
      indexes :status
      indexes :tags do
        indexes :name
      end
      indexes :foods do
        indexes :name
      end
    end
  end

  # http://localhost:9200/bwd_dev-items/_doc/#{article_id}?pretty=true
  def as_indexed_json(options = {})
    as_json(include: {
      tags: { only: [:name] },
      foods: { only: [:name] },
      restaurant: { only: [:id, :status] },
    })
  end

  def to_param
    "#{id}-#{name.parameterize}"
  end

  def get_review(user)
    reviews.where(user: user).first
  end
end
