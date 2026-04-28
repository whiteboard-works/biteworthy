Rails.application.routes.draw do
  root 'layouts#home'

  # Users
  get 'me',          to: 'users#show',        as: 'me'
  get 'my_points',   to: 'users#my_points',      as: 'my_points'
  get 'choose_tags', to: 'users#choose_tags', as: 'choose_tags'

  # Main Pages
  get 'about',            to: 'pages#about'
  get 'levels',           to: 'pages#levels'
  get 'privacy-policy',   to: 'pages#privacy_policy'
  get 'terms-of-service', to: 'pages#terms_of_service'

  get '/create_user_rating',            to: 'reviews#create_user_rating',                as: "create_user_rating"
  get '/restaurant_item_filter',        to: 'admin/items#restaurant_item_filter',        as: "restaurant_item_filter"

  # Basic routes
  resources :reports, only: [:new, :create]
  resources :ingredients, only: [:index, :show]
  resources :restaurants, only: [:index, :show] do
    resources :foods, :addresses, :extras, only: [:index, :show]
    resources :items, only: [:show] do
       resources :prices, only: [:index, :show]
     end
   end

  #Search
  get 'search', to: 'search#home'
  get 'ratings', to: 'users#ratings'
  get 'ingredient_search', to: 'search#ingredient_search'
  get 'food_search', to: 'search#food_search'
  get 'tag_search', to: 'search#tag_search'
  get 'choice_search', to: 'search#choice_search'
  get 'addition_search', to: 'search#addition_search'
  post 'search/advanced', to: 'search#advanced'

  resources :reviews, :tags
  get 'reviews/lookup', to: 'reviews#lookup', as: "lookup"

  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth', sessions: 'sessions' }

  namespace :admin do
    root 'layouts#home'
    resources :users, :tags, :points
    resources :ingredients do
      post 'add_tag', to: 'ingredients#add_tag', as: 'add_tag'
      post 'remove_tag', to: 'ingredients#remove_tag', as: 'remove_tag'
      resources :varieties
    end
    get 'ingredient-varieties', to: 'varieties#all'
    post 'add_parent_tag', to: 'tags#add_parent', as: 'add_parent_tag'
    post 'add_child_tag', to: 'tags#add_child', as: 'add_child_tag'
    post 'remove_tag_parent/:id', to: 'tags#remove_parent', as: 'remove_tag_parent'

    resources :restaurants do
      post 'remove_photo',      to: 'restaurants#remove_photo',      as: "remove_photo"
      resources :menus
      resources :menu_groups do
        post 'remove_item', to: 'foods#remove_item', as: "remove_item"
      end
      resources :addresses
      resources :items do
        resources :prices
        #add new X
        post 'add_new',           to: 'items#add_new',           as: "add_new"
        post 'add_new_tag',       to: 'items_ajax#add_new_tag',  as: "add_new_tag"
        post 'add_new_food',      to: 'items_ajax#add_new_food', as: "add_new_food"
        post 'add_new_extra',     to: 'items#add_new_extra',     as: "add_new_extra"
        post 'add_tag',           to: 'items_ajax#add_tag',      as: "add_tag"
        post 'add_foods',         to: 'items_ajax#add_foods',    as: "add_foods"
        post 'add_extra',         to: 'items#add_extra',         as: "add_extra"
        #remove new X
        post 'remove_menu_group', to: 'items#remove_menu_group', as: "remove_menu_group"
        post 'remove_tag',        to: 'items_ajax#remove_tag',   as: "remove_tag"
        post 'remove_tags',       to: 'items_ajax#remove_tags',  as: "remove_tags"
        post 'remove_food',       to: 'items_ajax#remove_food',  as: "remove_food"
        delete 'remove_extra',      to: 'items#remove_extra',      as: "remove_extra"
        post 'remove_photo',      to: 'items#remove_photo',      as: "remove_photo"
        post 'tag_up',            to: 'items_ajax#tag_up',       as: "tag_up"
      end

      resources :foods do
        post 'add_new_tag',            to: 'foods_ajax#add_new_tag',       as: "add_new_tag"
        post 'add_tag',                to: 'foods_ajax#add_tag',           as: "add_tag"
        post 'add_ingredient',         to: 'foods#add_ingredient',         as: "add_ingredient"
        post 'add_ingredient_by_name', to: 'foods#add_ingredient_by_name', as: "add_ingredient_by_name"
        post 'remove_ingredient',      to: 'foods#remove_ingredient',      as: "remove_ingredient"
        post 'remove_variety',         to: 'foods#remove_variety',         as: "remove_variety"
        post 'remove_photo',           to: 'foods#remove_photo',           as: "remove_photo"
        post 'remove_tag',             to: 'foods_ajax#remove_tag',        as: "remove_tag"
        post 'remove_tags',            to: 'foods_ajax#remove_tags',       as: "remove_tags"
        post 'tag_up',                 to: 'foods_ajax#tag_up',            as: "tag_up"
      end
      resources :extras do
        #price
        resources :prices
        #food
        post 'add_new_food',  to: 'extras_ajax#add_new_food',  as: "add_new_food"
        post 'add_foods',     to: 'extras_ajax#add_foods',     as: "add_foods"
        post 'remove_food',   to: 'extras_ajax#remove_food',   as: "remove_food"
        #photo
        post 'remove_photo',  to: 'extras#remove_photo',  as: "remove_photo"
        #Tag actions
        post 'add_new_tag',   to: 'extras_ajax#add_new_tag',  as: "add_new_tag"
        post 'add_tag',       to: 'extras_ajax#add_tag',      as: "add_tag"
        post 'remove_tag',    to: 'extras_ajax#remove_tag',   as: "remove_tag"
        post 'remove_tags',   to: 'extras_ajax#remove_tags',  as: "remove_tags"
        post 'tag_up',        to: 'extras_ajax#tag_up',       as: "tag_up"
      end
      post 'add_new_price', to: 'prices#add_new_price', as: "add_new_price"
      get 'get_menu_groups_by_restaurant', to: 'foods#get_menu_groups_by_restaurant', as: "get_menu_groups_by_restaurant"
    end

    resources :reports
    get 'menus',       to: 'menus#all',       as: "menus"
    get 'menu_groups', to: 'menu_groups#all', as: "menu_groups"
    get 'items',       to: 'items#all',       as: "items"
    get 'foods',       to: 'foods#all',       as: "foods"
    get 'revert_point/:id', to: 'points#revert_point', as: "revert_point"

    scope "items" do
      get 'add_tags',  to: 'items#add_tags',       as: "add_tags"
      post 'add_tags', to: 'items_ajax#add_tags',  as: "ajax_add_tags"
    end
    namespace :ajax do
      # Is this a wise route?
    end
  end

end
