module ApplicationHelper
  include Pagy::Frontend

  def price_to_s(price)
    if price >= 1
      "$#{number_with_precision(price, strip_insignificant_zeros: true)}"
    elsif price > 0
      "#{number_with_precision(price, precision: 2).sub(/^[0.]*/,"")}¢"
    elsif price != 0
      "#{price}"
    end
  end

  def show_image(object, ratio: "160x160", size: :four_by_three, image_class: "")
    if object.photos.present?
      image_tag object.photos.sample.image(size)
    else
      case object.class.to_s
      when "Restaurant"
        image_tag "logo_pic.png", ratio: ratio, class: image_class
      when "Item"
        image_tag "food_pic.png", ratio: ratio, class: image_class
      when "Food"
        image_tag "food_pic.png", ratio: ratio, class: image_class
      when "Tag"
        image_tag "image_here.png", ratio: ratio, class: image_class
      when "Extra"
        image_tag "image_here.png", ratio: ratio, class: image_class
      else
        image_tag "image_here.png", ratio: ratio, class: image_class
      end
    end
  end
end
