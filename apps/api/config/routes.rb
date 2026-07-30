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
      resource :profile, only: [:show, :update] do
        # Phase 4.8 — "My filtered menus" history (recent restaurant
        # visits with the visible/hidden item counts at view time).
        get :history, to: "profile_history#index"
        # The caller's own reviews for the account page — includes their
        # hidden reviews (unlike the public by-handle feed), newest first.
        get :reviews, to: "profile_reviews#index"
        # The caller's saved restaurants + dishes for the account page.
        get :favorites, to: "profile_favorites#index"
      end
      # Legal remediation E3 — JSON archive of the caller's personal
      # data (Privacy Policy "Access / export your data").
      get "/account/export", to: "account_exports#show"
      # Phase 5.6 — backs the SSR /durango/[diet] SEO pages. Flat
      # route (not nested) so the `:city_slug` param name is explicit.
      # There is no CitiesController yet, so only this restaurants-by-city
      # read is exposed; a bare `resources :cities` would 500.
      get "/cities/:city_slug/restaurants",
          to: "city_restaurants#index",
          as: :city_restaurants_ranking
      # Phase 6.2 — :create is the community "scan a new restaurant"
      # entrypoint (authenticated; pg_trgm dedup guard inside).
      resources :restaurants, only: [:index, :show, :create] do
        resources :items, only: [:index, :show]
        # Phase 4.9 — restaurant claim flow.
        post   "claim",        to: "restaurant_claims#create"
        get    "claim/verify", to: "restaurant_claims#verify"
        # Save/unsave a restaurant (authed).
        post   "favorite", to: "favorite_restaurants#create"
        delete "favorite", to: "favorite_restaurants#destroy"
        # Phase 4.10 — owner's pending-suggestion queue.
        resources :suggestions, only: [:index]
      end
      resources :ingredients, only: [:index]
      resources :tags, only: [:index]
      resources :dietary_profiles, only: [:index]
      resources :items, only: [] do
        member do
          post   :never_hide, to: "item_overrides#create"
          delete :never_hide, to: "item_overrides#destroy"
          # Save/unsave a dish (authed).
          post   :favorite, to: "favorite_items#create"
          delete :favorite, to: "favorite_items#destroy"
        end
        resources :reviews, only: [:index, :create]
        # Phase 4.10 — anyone can suggest a fix.
        resources :suggestions, only: [:create]
      end
      resources :reviews, only: [:update, :destroy] do
        # Legal remediation E8 — readers report a review into the
        # moderation queue.
        member { post :report }
      end
      # Phase 5.10 — soft-launch waitlist; public + unauthenticated.
      resources :waitlist_signups, only: [:create]
      # Legal remediation E10 — DMCA takedown intake; public.
      resources :dmca_notices, only: [:create]
      # Phase 4.10 — owner accepts/rejects a suggestion.
      resources :suggestions, only: [:update]
      # Phase 4.7 — public profile by handle. Constraint allows
      # underscores + digits + ASCII letters (matches User#handle
      # validation).
      get "/users/:handle", to: "users#show", as: :user, constraints: { handle: /[A-Za-z0-9_]{3,30}/ }
      resources :ingestion_runs, only: [:create, :show] do
        resources :items, only: [:index, :update], controller: "ingestion_items" do
          collection { post :accept_all }
        end
      end
      # The caller's own identity incl. `is_admin` — the web /admin
      # guard's probe. Read-only on purpose: auth/refresh also returns
      # the user payload but rotates the jti, killing other sessions.
      get "/me", to: "me#show"
      # Web-admin backoffice JSON namespace. Admin-only; non-admins get
      # 404 (see Api::V1::Admin::BaseController). Replaces Avo + the
      # ERB /admin/dashboard capability by capability.
      namespace :admin do
        get :dashboard, to: "dashboards#show"
        resources :ingestion_runs, only: [:index] do
          member { post :re_extract }
        end
        resources :restaurants, only: [] do
          member { post :confirm_community }
        end
      end
    end
  end

  # OpenAPI spec served via rswag (wired up in Phase 1.6).
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"
end
