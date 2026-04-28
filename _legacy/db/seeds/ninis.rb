module Ninis
   ninis                     = Restaurant.find_or_create_by(name: "Ninis", slogan: "Food so good you wont trust the water", main_image_url: "ninis.gif")
   default_menu              = ninis.menus.create

   ninis_burritos            = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Burritos",     description: "A flour tortilla with beans, rice, sour crea, cheese, salsa, and...")
   ninis_tacos               = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Tacos",        description: "Three soft flour or corn tortillas filled with sour cream, cheese, lettuce, salsa and...")
   ninis_quesadillas         = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Quesadillas",  description: "grilled flour torilla with melted chees, sour cream, salsa and...")
   mild_salsa_menu_group     = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Mild salsa",   description: nil)
   medium_salsa_menu_group   = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Medium salsa", description: nil)
   hot_salsa_menu_group      = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Hot Salsa",    description: nil)
   soup_and_salad_menu_group = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Salad, Soups & Other Stuff", description: nil)
   for_the_kids_menu_group   = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "For The Kids", description: nil)
   bebidas_menu_group        = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Bebidas", description: nil)
   extras_menu_group         = MenuGroup.find_or_create_by(restaurant_id: ninis.id, name: "Extras", description: nil)

   burrito_items = [
     ["Chicken burrito", nil, ninis_burritos, [{price: 7.50, size: "small"},{price: 8.75, size: "regular"}]],
     ["Barbacoa burrito", "Shredded beef", ninis_burritos, [{price: 7.50, size: "small"},{price: 8.75, size: "regular"}]],
     ["Carnitas burrito", "Shredded pork", ninis_burritos, [{price: 7.50, size: "small"},{price: 8.75, size: "regular"}]],
     ["Fish burrito", "Alaskan pollock with spicy coleslaw", ninis_burritos, [{price: 7.75, size: "small"},{price: 8.95, size: "regular"}]],
     ["Vegetarian burrito", "Mixed sauteed vegetables", ninis_burritos, [{price: 7.50, size: "small"},{price: 8.75, size: "regular"}]],
     ["Beans, rice, & salsa burrito", "Beans, rice, sour cream, cheese, and salsa", ninis_burritos, [{price: 6.25, size: "small"},{price: 7.25, size: "regular"}]],
   ]
   taco_items = [
      ["Chicken taco", nil, ninis_tacos, [{price: 8.25, size: nil}]],
      ["Carnitas taco", "Shredded pork", ninis_tacos, [{price: 8.25, size: nil}]],
      ["Barbacoa taco", "Shredded beef", ninis_tacos, [{price: 8.25, size: nil}]],
      ["Fish taco", "Alaskan Pollock with spicy coleslaw", ninis_tacos, [{price: 8.50, size: nil}]],
      ["Vegetarian taco", "Mixed sauteed vegetables", ninis_tacos, [{price: 8.25, size: nil}]],
      ["Individual taco", "Filled with choice ingredients.", ninis_tacos, [{price: 2.95, size: "each"}, {price: 3.25, size: "for fish"}]],
    ]
    quesadillas_items = [
      ["Chicken quesadilla", nil, ninis_quesadillas, [{price: 7.50, size: "small"},{price: 8.50, size: "regular"}]],
      ["Carnitas quesadilla", "Shredded pork", ninis_quesadillas, [{price: 7.50, size: "small"},{price: 8.50, size: "regular"}]],
      ["Barbacoa quesadilla", "Shredded beef", ninis_quesadillas, [{price: 7.50, size: "small"},{price: 8.50, size: "regular"}]],
      ["Fis quesadilla", "Alaskan Pollock with spicy coleslaw", ninis_quesadillas, [{price: 8.75, size: "small"},{price: 8.75, size: "regular"}]],
      ["Vegetarian quesadilla", "Mixed sauteed vegetables", ninis_quesadillas, [{price: 7.50, size: "small"},{price: 8.50, size: "regular"}]],
      ["Cheese quesadilla ", nil, ninis_quesadillas, [{price: 5.50, size: "small"},{price: 6.50, size: "regular"}]],
    ]

   salsa_items = [
     ["Corn & Black Beans",  "Mixture of corn blackbeans, tomatoes, lime, scallions, salt and pepper.", mild_salsa_menu_group, nil],
     ["Mango Lime",          "Blended mangos, limes ,red onions and jalapenos.", mild_salsa_menu_group, nil],
     ["Salsa Del Sol",       "Chunky tomato salsa with roasted green peppers, red onions, lime juice, cilantro, and salt - Salsa of the sun.", mild_salsa_menu_group, nil],
     ["Tomatillo",           "Blended tomatillos, jalapenos, bumin, onions - a salsa verde", medium_salsa_menu_group, nil],
     ["Pico De Gallo",       "A chucky tomato salsa wih jalapenos, cilantro, onions, lime and salt; means 'beak of the roaster'", medium_salsa_menu_group, nil],
     ["Roasted Roma Tomato", "Oven roasted roma tomatoes, onions, and jalapenos", medium_salsa_menu_group, nil],
     ["Roasted Serrano",     "Serrano chillies, tomatoes, oions, peppers, cilantro, cumin, salt, pepper, and vinagers", hot_salsa_menu_group, nil],
     ["Chipotle Puree",      "Blended adobo chillies with various spices, very smokey", hot_salsa_menu_group, nil],
     ["Mango Habanero",      "Freshly chopped mango, onions, habanero peppers, red peppers", hot_salsa_menu_group, nil],
   ]

   soup_and_salad_items = [
     ["Southwestern Fish Chowder", "variation of the original with southwestern flavours, served with tortilla or chips", soup_and_salad_menu_group, [{price: 5.50, size: nil}]],
     ["Tortilla Salad", "Shreadded lettuce, vinegarette dressing, chips, cheese, sour cream, & choice of 2 salsas. Add meat, rice, beans, fish or veggies for $1.50 each.", soup_and_salad_menu_group, [{price: 5.95, size: nil}]],
     ["Nachos", "tortilla chips with melted cheese, sour cream and salsa. Add meat, rice beans, fish or veggies for $1.50 each.", soup_and_salad_menu_group, [{price: 7.50, size: nil}]],
   ]

   for_the_kids_items = [
     ["El Raton", "kid size quesadilla", for_the_kids_menu_group,  [{price: 3.50, size: nil}]],
     ["El Bicho", "kid size quesadilla with chicken, pork, or beef.", for_the_kids_menu_group,  [{price: 3.95, size: nil}]],
   ]

   extra_items = [
     ["Homemade guacamole",      nil, extras_menu_group, [{price: 1.25, size: nil}]],
     ["Freshly made salsa",      nil, extras_menu_group, [{price: 0.75, size: nil}]],
     ["Freshly made 16oz salsa", nil, extras_menu_group, [{price: 7.95, size: nil}]],
     ["Spicy coleslaw",          nil, extras_menu_group, [{price: 1,    size: nil}]],
     ["Side of beans or rice",   nil, extras_menu_group, [{price: 1.5,  size: nil}]],
     ["Sour cream",              nil, extras_menu_group, [{price: 0.5,  size: nil}]],
     ["Cheese",                  nil, extras_menu_group, [{price: 1,    size: nil}]],
     ["Side of tortilla chips",  nil, extras_menu_group, [{price: 1.95, size: nil}]],
   ]

   bebidas_items = [
     ["Sodas", nil, bebidas_menu_group, nil],
     ["Beer", nil, bebidas_menu_group, nil],
     ["Margaritas", nil, bebidas_menu_group, nil]
   ]
   ninis_items = burrito_items + taco_items +  quesadillas_items + salsa_items + soup_and_salad_items + for_the_kids_items +  bebidas_items + extra_items
   ninis_items.each do |name, description, menu_group, prices_sizes|
     menu_group.menus << default_menu
     item = Item.find_or_create_by(restaurant: ninis,
      name: name,
      description: description)
      item.menu_groups << menu_group unless item.menu_groups.include? menu_group
      if prices_sizes
        prices_sizes.each do |price_size|
          Price.find_or_create_by(value: price_size[:price], size: price_size[:size], priced_id: item.id, priced_type: "Item")
        end
      end
      item.save
   end

   puts "Ninis seeded"
end
