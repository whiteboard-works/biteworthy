# JWT auth wiring for the BiteWorthy API.
#
# Strategy: devise-jwt's JTIMatcher revocation. Each User row carries a
# `jti` (JWT ID) column. A JWT is valid only when its `jti` claim
# matches the user's current `jti`. Logout rotates the column; refresh
# also rotates so that the previous access token is invalidated as
# soon as a new one is issued.
#
# Dispatch / revocation request matching is configured through Devise's
# .jwt block — devise-jwt 0.12.x reads the config from there at boot.

Devise.setup do |config|
  config.jwt do |jwt|
    jwt.secret = Rails.application.credentials.devise_jwt_secret_key.presence ||
                 ENV["DEVISE_JWT_SECRET_KEY"].presence ||
                 Rails.application.secret_key_base

    # Tokens are dispatched on signup + login. Refresh is handled
    # manually by SessionsController#refresh — it must accept an
    # incoming token (which the JWT strategy skips on dispatch paths)
    # and emit a fresh one in the same response.
    jwt.dispatch_requests = [
      ["POST", %r{^/api/v1/auth/signup$}],
      ["POST", %r{^/api/v1/auth/login$}]
    ]
    # Tokens are revoked on logout.
    jwt.revocation_requests = [
      ["DELETE", %r{^/api/v1/auth/logout$}]
    ]

    jwt.expiration_time = 30.minutes.to_i
  end
end
