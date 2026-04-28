class Ingredient < ActiveRecord::Base
  include TrackPoints
  has_closure_tree
  before_validation :set_normalized_name
  belongs_to :user

  has_many :photos, as: :photo

  has_many :items, through: :items_ingredients
  has_many :items_ingredients

  has_many :foods, through: :foods_ingredients
  has_many :foods_ingredients

  has_many :tags, through: :ingredients_tags
  has_many :ingredients_tags

  has_many :varieties, dependent: :destroy

  validates :name, :normalized_name, presence: true
  validates :normalized_name, uniqueness: true
  has_many :reviews, as: :review
  attr_accessor :variety

  scope :ingredients_created, ->(user) { where(user: user).count }

  def to_param
    normalized_name
  end

  def set_normalized_name
    self.normalized_name = self.name.parameterize.singularize
  end

  def get_review(user)
    reviews.where(user: user).first
  end
end
