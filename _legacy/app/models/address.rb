class Address < ActiveRecord::Base
  include TrackPoints
  belongs_to :restaurant
end
