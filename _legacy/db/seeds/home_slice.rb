module Dsp
  home_slice              = Restaurant.find_or_create_by(name: "Home Slice", slogan: "")
  default_menu         = home_slice.menus.create

  home_slice_single_slice = MenuGroup.find_or_create_by(restaurant_id: home_slice.id, name: "Single Slice", description: "Basic pizza with...")
  home_slice_single_slice.menus << default_menu

  cheese_slice = Item.find_or_create_by(restaurant_id: home_slice.id, menu_group_id: home_slice_single_slice.id, name: "Cheese", description: "")
cheese_slice.up
sauces = " marinara, garlic oil, garlic butter, bbq, alfredo, pesto, ranch, spicy thai coconut, buffalo sauce"

cheeses = "feta "

  # cheese = Food.find_or_create_by(restaurant_id: dsp.id, name: "Cheese")
  # cheese_slice.foods << cheese

  puts "Home slice seeded"
end
