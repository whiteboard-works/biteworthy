# Shared JWT + JSON-payload helpers for the auth controllers
# (Registrations, Sessions, OmniauthCallbacks). The signup/login `create`
# actions let devise-jwt's `sign_in(store: false)` dispatch hook set the
# header automatically; `refresh` and the OmniAuth callback mint a token
# manually and use `set_jwt_header`.
module AuthTokenResponse
  extend ActiveSupport::Concern

  private

  # The user fields every auth response returns. `provider` is opt-in so
  # the email signup/login payloads stay exactly as they were — only the
  # OAuth callback advertises which provider authenticated.
  def user_payload(user, include_provider: false)
    payload = {
      id: user.id,
      email: user.email,
      handle: user.handle,
      display_name: user.display_name,
      is_admin: user.is_admin
    }
    payload[:provider] = user.provider if include_provider
    payload
  end

  # Mints a fresh JWT for `user` and writes it to the response
  # Authorization header — the same path devise-jwt's dispatch hook uses
  # on create. UserEncoder reads `jwt.expiration_time` + `jwt.secret`
  # from the initializer.
  def attach_jwt_header(user)
    token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    response.set_header("Authorization", "Bearer #{token}")
  end
end
