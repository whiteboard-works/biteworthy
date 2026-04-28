class Point < ActiveRecord::Base
  include CacheInvalidator
  after_create :invalidate_cache

  belongs_to :user
  #TODO polymorphic associations
  belongs_to :object, polymorphic: true

  enum change_types: [:create_object, :update_object, :join_object, :destroy_object]

  def display_change_type
    case change_type
    when 0
      "Create"
    when 1
      "Update"
    when 2
      "Join"
    when 3
      "Destroy"
    else
      "42"
    end
  end
end
