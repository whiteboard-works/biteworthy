module Himalayan
   himalayan = Restaurant.find_or_create_by(name: "Himalayan Kitchen", slogan: "Mountain food for mountain people", main_image_url: 'himalayan.jpg')
   default_menu         = himalayan.menus.create

   starters_menu_group   = MenuGroup.find_or_create_by(restaurant: himalayan, name: "Starters", description: "")
   soup_salad_menu_group = MenuGroup.find_or_create_by(restaurant: himalayan, name: "Soup & Salad", description: "")
   starters_menu_group.menus   << default_menu
   soup_salad_menu_group.menus << default_menu

   starter_items =[
     ["Mo-mo", "A very popular dish among Nepalese and Tibetains. These steamed dumplings are filled with your choice of veggie, chicken, lamb or any combination and served with achaar.", 12.99],
     ["Veggie Samosas", "Chrisp puffed turnovers stuffed with potatoes green peas, onion, cumin, and coriander seed. Served with dipping sauce.", 5.99],
     ["Bhaktapure Chhoila", "Roasted lamb marinated with green chili, red onion, spring onion, cilantro, ginger garlic a toch of lime, and balsamic vinegar.", 10.99],
     ["Chicken Pakoda", "Fried chicken strips battered with chickpeas, flour, ginger, and garlic served with dippig sauce.", 7.99],
     ["Cheese Pakoda", "House made cheese battered with chickpeas, flour, ginger, and garlic served with dipping sauce.", 5.99],
     ["Sampling platter", "Combination of potatos salad, chicken Tandoori, vegetable mo-mo, and cheese pakora served wtih dipping sauce.", 11.99],
   ]

   starter_items.each do |name, description, price|
     item = Item.find_or_create_by(restaurant: himalayan, name: name, description: description)
     item.update(menu_groups: [starters_menu_group])
     Price.find_or_create_by(value: "price", priced_id: item.id, priced_type: "Item")
   end

   soup_salad_items = [
     ["Soup of the Day", "Please ask your server", 4.99],
     ["Tomato Soup", "Please ask your server", 4.99],
     ["Kachumbar Salad", "Diced cucumber, tomato, and onions marinated with lime juice dressing.", 5.99],
   ]

   soup_salad_items.each do |name, description, price|
     item = Item.find_or_create_by(restaurant: himalayan, name: name, description: description)
     item.update(menu_groups: [soup_salad_menu_group])
     Price.find_or_create_by(value: price, priced_id: item.id, priced_type: "Item")
   end

   puts "Himalayan seeded"
end
