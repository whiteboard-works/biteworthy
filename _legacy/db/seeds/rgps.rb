module Rgps
  rgps  = Restaurant.find_or_create_by(name: "RGP's", slogan: "A True Mom & Pop Sandwich Shop", main_image_url: "rgps.jpg")
  default_menu    = rgps.menus.create

  rgps_wraps  = MenuGroup.find_or_create_by(restaurant_id: rgps.id, name: "Flame Grilled Wraps", description: "Served warm on our flame grilled crusts & come with choice of REGULAR OR BARBECUE potato chips or cole slaw")
  rgps_salads = MenuGroup.find_or_create_by(restaurant_id: rgps.id, name: "Salads",              description: "Add Chicken to any salad for $1.50")
  rgps_kids   = MenuGroup.find_or_create_by(restaurant_id: rgps.id, name: "Kids",                description: "Add Chicken to any salad for $1.50")

  rgps_wraps.menus << default_menu
  rgps_salads.menus << default_menu
  rgps_kids.menus << default_menu

  rgps_wrap_items = [
    ["Chicken Pesto",
      "Oven roasted chicken breast, basil pesto, tomato and mozzarella cheese",
      [{price: 7.41, size: nil}],
      "chicken breast, basil pesto, tomato, mozzarella cheese",
      nil,
      rgps_wraps],
    ["Potato Ranch",
      "Crumbled bacon, roasted potatoes, cheddar cheese, tomato, red onion and ranch dressing",
      [{price: 7.41, size: nil}],
      "bacon, roasted potatoes, cheddar cheese, tomato, red onion, ranch dressing",
      nil,
      rgps_wraps],
    ["Cajun",
      "Oven roasted chicken breast, andouille sausage, red onion, green pepper, seasoned rice and SPICY ranch dressing",
      [{price: 6.99, size: nil}],
      "chicken breast, andouille sausage, red onion, green pepper, seasoned rice, SPICY ranch dressing",
      nil,
      rgps_wraps],
    ["BBQ Pork",
      "Pulled pork, cheddar cheese, red onion, black beans and tangy BBQ sauce",
      [{price: 6.99, size: nil}],
      "Pulled pork, cheddar cheese, red onion, black beans, tangy BBQ sauce",
      nil,
      rgps_wraps],
    ["Southwest Turkey",
      "Oven roasted turkey breast, crumbled bacon, cheddar cheese, green chili, tomato and SPICY chipotle dressing",
      [{price: 7.41, size: nil}],
      "turkey breast, bacon, cheddar cheese, green chili, tomato, SPICY chipotle dressing",
      nil,
      rgps_wraps],
    ["Superman",
     "Oven roasted chicken breast, crumbled bacon, basil pesto, mozzarella cheese, feta cheese, tomato, red onion and SPICY ranch dressing",
      [{price: 7.88, size: nil}],
     "chicken breast, bacon, basil pesto, mozzarella cheese, feta cheese, tomato, red onion, SPICY ranch dressing",
      nil,
      rgps_wraps],
    ["GYRO",
     "Seasoned lamb, feta cheese, red onion, tomato, romaine lettuce and tzatziki dressing",
      [{price: 7.88, size: nil}],
     "lamb, feta cheese, red onion, tomato, romaine lettuce, tzatziki dressing",
      nil,
      rgps_wraps],
    ["Chris and Jen",
     "Oven Roasted Turkey breast, crumbled bacon, cheddar cheese, feta cheese, tomato, red onion, carrots, green pepper, coleslaw and SPICY ranch dressing",
      [{price: 7.41, size: nil}],
     "Turkey breast, bacon, cheddar cheese, feta cheese, tomato, red onion, carrots, green pepper, coleslaw, SPICY ranch dressing",
      nil,
      rgps_wraps],
    ["Greek",
      "Oven roasted Chicken breast, feta cheese, tomato, red onion, black olives, romaine lettuce and greek dressing",
      [{price: 6.99, size: nil}],
      "Chicken breast, feta cheese, tomato, red onion, black olives, romaine lettuce, greek dressing",
      nil,
      rgps_wraps],
    ["Fajita",
      "Oven roasted chicken breast, cheddar cheese, red onion, green pepper, sour cream, romaine lettuce, fajita seasoning and salsa",
      [{price: 6.99, size: nil}],
      "chicken breast, cheddar cheese, red onion, green pepper, sour cream, romaine lettuce, fajita seasoning, salsa",
      nil,
      rgps_wraps],
    ["Chicken or Turkey",
      "Oven Roasted Chicken or Turkey breast, tomato, red onion, green pepper, carrots, romaine lettuce",
      [{price: 7.41, size: nil}],
      "Chicken breast, Turkey breast, tomato, red onion, green pepper, carrots, romaine lettuce",
      "Cheese, Dressing, Chicken or Turkey",
      rgps_wraps],
    ["BLT",
      "Crumbled bacon, provalone cheese, tomato, romaine lettuce and caesar dressing",
      [{price: 6.99, size: nil}],
      "bacon, provavone cheese, tomato, romaine lettuce, caesar dressing",
      nil,
      rgps_wraps],
    ["Reuben",
      "Corned beef round, swiss cheese, sauerkraut, 1,000 island dressing",
      [{price: 7.88, size: nil}],
      "Corned beef round, swiss cheese, sauerkraut, 1,000 island dressing",
      nil,
      rgps_wraps],
    ["Spicy Buffalo",
      "Oven Roasted Chicken breast, gorgonzola cheese, mozzarella cheese, red onion, romaine lettuce and SPICY marinara sauce",
      [{price: 6.99, size: nil}],
      "Chicken breast, gorgonzola cheese, mozzarella cheese, red onion, romaine lettuce, SPICY marinara sauce",
      nil,
      rgps_wraps],
    ["Chicken Caesar",
      "Oven Roasted Chicken breast, romano cheese, romaine lettuce and caesar dressing",
      [{price: 6.99, size: nil}],
      "Chicken breast, romano cheese, romaine lettuce, caesar dressing",
      nil,
      rgps_wraps],
    ["Veggie Man",
      "Basil pesto, Feta cheese, mozzarella cheese, red onion, roasted red peppers, roasted potatoes and SPICY ranch dressing",
      [{price: 7.41, size: nil}],
      "Basil pesto, Feta cheese, mozzarella cheese, red onion, roasted red peppers, roasted potatoes, SPICY ranch dressing",
      "Cheese, Dressing",
      rgps_wraps],
    ["Vegtastic",
      "Black beans, cheddar cheese, green chili, tomato, red onion, roasted potatoes, romaine lettuce, and SPICY chipotle dressing",
      [{price: 7.41, size: nil}],
      "Black beans, cheddar cheese, green chili, tomato, red onion, roasted potatoes, romaine lettuce, SPICY chipotle dressing",
      "Cheese, Dressing",
      rgps_wraps],
    ["Standard Veggie",
      "Sweet roasted red peppers, sweet corn, tomato, red onion, green pepper, carrots, crisp romaine lettuce and choice of Cheese and Dressing",
      [{price: 6.99, size: nil}],
      "red peppers, sweet corn, tomato, red onion, green pepper, carrots, romaine lettuce",
      "Cheese, Dressing",
      rgps_wraps],
  ]


  rgps_salad_items = [
    ["House",
      "Romaine lettuce, roasted red peppers, red onion, carrots, green peppers, tomato, croutons and choice of dressing",
      [{price: 5.95, size: nil}, {price: 1.75, size: "Add Chicken or Turkey"}],
      "Romaine lettuce, roasted red peppers, red onion, carrots, green peppers, tomato, croutons",
      "Dressing",
      rgps_salads],
    ["Greek",
      "Romaine lettuce, black olives, tomato, red onion, feta cheese and greek dressing",
      [{price: 5.95, size: nil}, {price: 1.75, size: "Add Chicken or Turkey"}],
      "Romaine Lettuce, black olives, tomato, red onion, feta cheese, greek dressing",
      nil,
      rgps_salads],
    ["Caesar",
      "Romaine lettuce, pecorino romano cheese, croutons and caesar dressing",
      [{price: 5.95, size: nil}, {price: 1.75, size: "Add Chicken or Turkey"}],
      "Romaine Lettuce, Pecorino Romano Cheese, croutons, caesar Dressing",
      nil,
      rgps_salads],
    ["Cheese Pizza",
      "Small Cheese pizza",
      [{price: 5.95, size: nil}],
      "",
      nil,
      rgps_kids],
    ["Cheese Quesadilla",
      "",
      [{price: 5.95, size: nil}],
      "",
      nil,
      rgps_kids],
  ]


  rgps_items = rgps_wrap_items + rgps_salad_items
  rgps_side = Extra.find_or_create_by(name: "Regular OR Barbecue Chips OR coleslaw", description: "Regular OR Barbecue Chips OR coleslaw", restaurant: rgps, addon_type: "choice")
  rgps_side.foods.create(name: "coleslaw")
  rgps_side.foods.create(name: "Regular Potato chips", description: "Lays regular potato chips")
  rgps_side.foods.create(name: "BBQ Potato chips", description: "Lays BBQ potato chips")

  rgps_items.each do |name, description, prices_sizes, foods_array, extras_array, menu_group|
    item = Item.find_or_create_by(restaurant: rgps,
      name: name,
      description: description,
    )
    item.menu_groups << menu_group
    if menu_group == rgps_wraps
        item.extras << rgps_side
    end
    foods_array.split(', ').each do |food|
      food = Food.find_or_create_by(name: food.downcase, restaurant: rgps)
      item.foods << food
    end
    if extras_array
      extras_array.split(', ').each do |extra_name|
        extra = Extra.where(name: extra_name.downcase, restaurant: rgps, addon_type: Extra.choice).first_or_create
        item.extras << extra if extra
      end
    end
    item.save

     prices_sizes.each do |price_size|
       item.prices.create(value: price_size[:price], size: price_size[:size])
     end
  end
  puts "Rgps seeded"
end
