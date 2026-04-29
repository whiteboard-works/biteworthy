# OmniAuth 2.x defaults to POST-only for the request phase as a CSRF
# mitigation. BiteWorthy's mobile + web clients hit OAuth start URLs
# via redirect (a GET), which is the standard pattern when there's no
# DOM to render a form into. Allowing GET here is safe because the
# `omniauth-rails_csrf_protection` gem (already in the Gemfile)
# enforces CSRF on the *callback* phase — which is the side that
# actually receives untrusted input from the provider.
OmniAuth.config.allowed_request_methods = [:get, :post]
OmniAuth.config.silence_get_warning = true

# Mount OmniAuth's internal middleware under the same /api/v1/auth/
# prefix the rest of the auth routes use. Without this, OmniAuth would
# only intercept /auth/<provider>/callback URLs, which our routes
# don't expose.
OmniAuth.config.path_prefix = "/api/v1/auth"

# In test mode, fail fast on misconfigured mocks so missing-mock bugs
# surface in the spec instead of silently 302'ing to /users/sign_in.
OmniAuth.config.test_mode = true if Rails.env.test?

# Translate OmniAuth's verbose strategy errors into our JSON failure
# response (handled by Api::V1::Auth::OmniauthCallbacksController#failure).
OmniAuth.config.on_failure = proc { |env|
  Api::V1::Auth::OmniauthCallbacksController.action(:failure).call(env)
}
