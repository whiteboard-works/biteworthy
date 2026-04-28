class UsersRole < ActiveRecord::Base

  enum role_types: [:owner, :dam, :employee]

end
