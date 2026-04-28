class Hour < ActiveRecord::Base
  #  has_and_belongs_to_many :items, dependent: :destroy
  enum day: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday,
    :everyday, :weekdays, :weekends]

  belongs_to :hour, polymorphic: true

  validates :day, :opens, :closes, presence: true

end
