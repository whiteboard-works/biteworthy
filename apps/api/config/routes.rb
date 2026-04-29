Rails.application.routes.draw do
  # Health check for uptime monitors and load balancers.
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise lives at /api/v1/auth/* with the standard `:user` resource
  # scope so request bodies use { user: { ... } } — not the auto-
  # generated `:api_v1_user` you'd get from a Rails namespace block.
  devise_for :users,
             path: "api/v1/auth",
             path_names: { sign_in: "login", sign_out: "logout", registration: "signup" },
             controllers: {
               sessions:      "api/v1/auth/sessions",
               registrations: "api/v1/auth/registrations"
             },
             defaults: { format: :json }

  # Custom Devise route — needs the devise_scope wrapper so the
  # SessionsController inherits the right Devise mapping.
  devise_scope :user do
    post "/api/v1/auth/refresh", to: "api/v1/auth/sessions#refresh", as: :api_v1_auth_refresh
  end

  namespace :api do
    namespace :v1 do
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

  # OpenAPI spec served via rswag (wired up in Phase 1.6).
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"
end
