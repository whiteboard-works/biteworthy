class AdminController < ApplicationController
  before_filter :authenticate_user!, :must_have_permission

  def must_have_permission
    redirect_to root_path if !current_user.is_admin?
  end

  def only_nom
    redirect_to root_path if !current_user.nom?
  end

  def home
  end

  def save_images(object, images)
    images.each do |image|
      object.photos.new(user_id: current_user.id, photo_type: object.class.to_s, image: image).save
    end
  end
end
