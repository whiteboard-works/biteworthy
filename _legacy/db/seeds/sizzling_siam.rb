module SizzlingSiam
   siam         = Restaurant.find_or_create_by(name: "Sizzling Siam", slogan: "Authentic Thai food", main_image_url: "sizzling_siam.jpg")
   default_menu = siam.menus.create

   siam_noodles = MenuGroup.find_or_create_by(restaurant_id: siam.id, name: "Noodle Dishes", description: "Rice noodles and...")
   siam_noodles.menus << default_menu

   item = Item.find_or_create_by(restaurant_id: siam.id, name: "Pad Thai", description: "With Tofu")
   item.menu_groups << siam_noodles
   item.save
   puts "Sizzling Siam seeded"
end
