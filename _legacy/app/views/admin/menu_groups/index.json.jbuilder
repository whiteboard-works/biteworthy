json.array!(@restaurant_menu_groups) do |restaurant_menu_group|
  json.extract! restaurant_menu_group, :id, :restaurant_id, :name, :description
  json.url restaurant_menu_group_url(restaurant_menu_group, format: :json)
end
