class Variety < ActiveRecord::Base
  include TrackPoints
  before_validation :set_normalized_name
  belongs_to :ingredient
  has_many :foods, through: :foods_varieties
  has_many :foods_varieties
  validates_uniqueness_of :name, scope: [:ingredient_id]

  def set_normalized_name
    self.name = self.name.parameterize.singularize
  end

  def display_name
    ingredient_first ? "#{ingredient.name} #{name}" : "#{name} #{ingredient.name}"
  end
end
