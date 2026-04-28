class PagesController < ApplicationController


  def levels
    @good_levels = User.good_level_info
    @bad_levels = User.bad_level_info
  end

  def about
  end

  def privacy_policy
  end

  def terms_of_service
  end

end



