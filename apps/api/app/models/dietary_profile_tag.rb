class DietaryProfileTag < ApplicationRecord
  belongs_to :dietary_profile
  belongs_to :tag
end
