module ThaiKitchen
   thai_k  = Restaurant.find_or_create_by(name: "Thai Kitchen", slogan: "")
   default_menu = thai_k.menus.create


   puts "ThaiKitchen seeded"
end
