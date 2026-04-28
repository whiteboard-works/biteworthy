module Dsp
  dsp              = Restaurant.find_or_create_by(name: "DSP", slogan: "New York style pizza",
  main_image_url: "dsp.png")
  default_menu         = dsp.menus.create

  dsp_single_slice = MenuGroup.find_or_create_by(restaurant_id: dsp.id, name: "Single Slice", description: "Basic pizza with...")
  dsp_single_slice.menus << default_menu

  cheese_slice = Item.find_or_create_by(restaurant_id: dsp.id, name: "Cheese", description: "Traditional slice of cheese pizza")
  cheese_slice.menu_groups << dsp_single_slice

  toppings = "Pepperoni, Italian Sausage, Canadian Bacon, Chicken, Anchovies, Green Peppers, Peperoncini, Jalepeños, Geeen Chillies, Onions, Roasted Onions, Green Olives, Black Olives, Feta, Blue Cheese, Extra Cheese, Spinish, Fresh Basil, Sundried tomatoes, Roma Tomatoes, Mushrooms, Garlic, Artichoke hearts, Pineapple"

  topping_extras = []
  toppings.split(', ').each do |topping|
    topping_extras << Food.find_or_create_by(name: topping, restaurant: dsp)
  end

  toppings_extra = Extra.find_or_create_by(name: "Toppings", restaurant: dsp, addon_type: Extra.addition)
  toppings_extra.foods = topping_extras

  puts "Dsp seeded"
end
