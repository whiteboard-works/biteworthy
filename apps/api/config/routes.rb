Rails.application.routes.draw do
  # Health check for uptime monitors and load balancers.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      devise_for :users,
                 controllers: { sessions: "api/v1/sessions", registrations: "api/v1/registrations" },
                 path: "auth",
                 path_names: { sign_in: "login", sign_out: "logout", registration: "signup" }

      resource :profile, only: [:show, :update]
      resources :cities, only: [:index, :show]
      resources :restaurants, only: [:index, :show] do
        resources :items, only: [:index, :show]
      end
      resources :ingredients, only: [:index]
      resources :tags, only: [:index]
      resources :dietary_profiles, only: [:index]
    end
  end

  # OpenAPI spec served via rswag.
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"
end
