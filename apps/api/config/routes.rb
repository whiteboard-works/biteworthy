Rails.application.routes.draw do
  mount_avo
  # Phase 2.9 cost dashboard. Lives at /admin/dashboard so the admin
  # nav bar can link straight to it from Avo.
  get "/admin/dashboard", to: "admin/dashboard#index", as: :admin_dashboard

  # Health check for uptime monitors and load balancers.
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise lives at /api/v1/auth/* with the standard `:user` resource
  # scope so request bodies use { user: { ... } } — not the auto-
  # generated `:api_v1_user` you'd get from a Rails namespace block.
  devise_for :users,
             path: "api/v1/auth",
             path_names: { sign_in: "login", sign_out: "logout", registration: "signup" },
             controllers: {
               sessions:            "api/v1/auth/sessions",
               registrations:       "api/v1/auth/registrations",
               omniauth_callbacks:  "api/v1/auth/omniauth_callbacks"
             },
             # devise_for would mount omniauth at /api/v1/auth/auth/:provider,
             # which doubles up the /auth segment. We skip it and define our
             # own clean routes below so the public URL is /api/v1/auth/:provider.
             skip: [:omniauth_callbacks],
             defaults: { format: :json }

  # Custom Devise route — needs the devise_scope wrapper so the
  # SessionsController inherits the right Devise mapping.
  devise_scope :user do
    post "/api/v1/auth/refresh", to: "api/v1/auth/sessions#refresh", as: :api_v1_auth_refresh

    # OmniAuth start + callback. Routes match what OmniAuth.config.path_prefix
    # tells the OmniAuth middleware to intercept; the start path passes through
    # the middleware (passthru), the callback path lands on our action that
    # mints a JWT. Constraints lock the :provider param to known strategies.
    provider_constraint = { provider: /google_oauth2|apple/ }
    match "/api/v1/auth/:provider",
          to: "api/v1/auth/omniauth_callbacks#passthru",
          via: [:get, :post], constraints: provider_constraint, as: :user_omniauth_authorize
    get   "/api/v1/auth/google_oauth2/callback",
          to: "api/v1/auth/omniauth_callbacks#google_oauth2",
          as: :user_google_oauth2_omniauth_callback
    get   "/api/v1/auth/apple/callback",
          to: "api/v1/auth/omniauth_callbacks#apple",
          as: :user_apple_omniauth_callback
    match "/api/v1/auth/failure",
          to: "api/v1/auth/omniauth_callbacks#failure",
          via: [:get, :post]
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
      resources :items, only: [] do
        member do
          post   :never_hide, to: "item_overrides#create"
          delete :never_hide, to: "item_overrides#destroy"
        end
        resources :reviews, only: [:index, :create]
      end
      resources :reviews, only: [:update, :destroy]
      resources :ingestion_runs, only: [:create, :show] do
        resources :items, only: [:index, :update], controller: "ingestion_items"
      end
    end
  end

  # OpenAPI spec served via rswag (wired up in Phase 1.6).
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"
end
