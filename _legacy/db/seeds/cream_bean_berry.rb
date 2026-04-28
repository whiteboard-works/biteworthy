module CreamBeanBerry
  cbb          = Restaurant.find_or_create_by(name: "Cream Bean Berry", slogan: "Eat Good. Feel Good.",
    about: "Our ice cream is made from scratch with 100% percent organic milk, crea, and sugar. We user as many local ingredients as possible. We reduce our waste through recycling and biodegradable packaging.",
    main_image_url: "cbb.png")

  default_menu         = cbb.menus.create
  cbb_ice_cream   = MenuGroup.find_or_create_by(restaurant: cbb, name: "Ice Cream Servings", description: "")
  cbb_drinks      = MenuGroup.find_or_create_by(restaurant: cbb, name: "Drinks", description: "")
  cbb_specialties = MenuGroup.find_or_create_by(restaurant: cbb, name: "Specialities", description: "")
  cbb_drinks.menus      << default_menu
  cbb_ice_cream.menus   << default_menu
  cbb_specialties.menus << default_menu

  cbb_ice_cream_items = [
     ["Mini Scoop",   nil, cbb_ice_cream, [{price:2.75, size: nil}, {price: 2.25, size: "with cone"}, {price: 3.75, size: "with waffle cone"}]],
     ["Single Scoop", nil, cbb_ice_cream, [{price: 3.50, size: nil}, {price: 4.00, size: "with cone"}, {price: 4.50, size: "with waffle cone"}]],
     ["Double Scoop", nil, cbb_ice_cream, [{price: 6.00, size: nil}, {price: 6.50, size: "with cone"}, {price: 7.00, size: "with waffle cone"}]],
     ["Pint",         nil, cbb_ice_cream, [{price: 8.00, size: nil}]],
     ["Quart",        nil, cbb_ice_cream, [{price: 14.00, size: nil}]],
     ["'Growler'",    nil, cbb_ice_cream, [{price: 12.00, size: "5$ jar deposit"}, {price: 7.00, size: "Refills"}]],
   ]
    cbb_drinks_items = [
      ["Zuberfizz Float",  "Two scoops of ice cream + Zufferfizz soda",     cbb_drinks, [{price: 6.25}]],
      ["Milk Shake",       "Your choice of ice cream",                      cbb_drinks, [{price: 6.00}]],
      ["Malt",             "Milk shake and malted milk powder",             cbb_drinks, [{price: 6.50}]],
      ["Frappé",           "Cold-brew coffee(organinc)+ice cream, blended", cbb_drinks, [{price: 6.50}]],
      ["Green tea Shake",  "Match green tea + ice cream, blended",          cbb_drinks, [{price: 6.50}]],
      ["Chai tea Shake",   "Blue Lotus Chai + ice cream, blended",          cbb_drinks, [{price: 6.50}]],
      ["Lemon Maté Shake", "Yerba Maté, lemon oil, ice cream, blended",     cbb_drinks, [{price: 6.50}, {price: 3.25}]],
      ["Sorbet Fizz",      "Sorbet + Fever Tree tonic water",               cbb_drinks, [{price: 6.25}, {price: 3.25}]],
    ]

    cbb_specialties_items = [
      ["Ice Cream Sandwich", "Hose baked cookies & ice cream",                                       cbb_specialties, [{price: 4.50, size: nil}]],
      ["Ice Cream Pop",      "Mini-scoop of ice cream, dipped in chocolate, garnished with topping", cbb_specialties, [{price: 2.50, size: nil}]],
      ["Ice Cream Cake",     "Made to order (gluten-free, add $2)",                                  cbb_specialties, [{price: 34.00, size: "small"},{price: 47.00, size: "large"}]],
      ["Ice Cream Pie",      "Made to order",                                                        cbb_specialties, [{price: 25, size: nil}]],
    ]

    cbb_items = cbb_ice_cream_items +  cbb_drinks_items + cbb_specialties_items
    cbb_items.each do |name, description, menu_group, prices_sizes|
      item = Item.find_or_create_by(restaurant: cbb,
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

   puts "Cream Bean berry seeded"
end