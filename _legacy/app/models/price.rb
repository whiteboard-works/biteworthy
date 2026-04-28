class Price < ActiveRecord::Base
  include TrackPoints
  belongs_to :priced, polymorphic: true

  validates :value, presence: true

  def to_s
    number_with_precision(price, strip_insignificant_zeros: true);
  end

end
