class Restaurant < ActiveRecord::Base
  include TrackPoints
  has_many :users, dependent: :destroy
  has_many :menus, dependent: :destroy
  has_many :menu_groups, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :foods, dependent: :destroy
  has_many :reviews, as: :review
  has_many :photos, as: :photo
  has_and_belongs_to_many :tags
  has_many :addresses, dependent: :destroy

  accepts_nested_attributes_for :addresses

  validates :name, presence: true

  scope :active, -> {where(active: true)}

  # searchable do
  #   text    :name
  #   text    :slogan
  #   text    :about
  #   boolean :active
  #   text    :tags do
  #     tags.map { |tag| tag.name }
  #   end
  # end

  def to_param
    "#{id}-#{name.parameterize}"
  end
end
