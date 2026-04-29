module OmniauthHelpers
  # Build an OmniAuth::AuthHash mimicking what Google or Apple would
  # POST back to our callback. Keeps the spec readable — call with
  # only the fields the test cares about.
  def omniauth_hash(provider:, uid: "uid-#{SecureRandom.hex(4)}",
                    email: "oauth-#{SecureRandom.hex(4)}@example.com",
                    name: "OAuth User")
    OmniAuth::AuthHash.new(
      provider: provider.to_s,
      uid: uid,
      info: { email: email, name: name },
      credentials: { token: "fake-token-#{SecureRandom.hex(4)}" }
    )
  end

  # Wire a mocked auth payload into OmniAuth so the next request to
  # /api/v1/auth/<provider>/callback resolves to it instead of hitting
  # the live provider.
  def mock_omniauth(provider, auth)
    OmniAuth.config.mock_auth[provider.to_sym] = auth
    Rails.application.env_config["devise.mapping"]      = Devise.mappings[:user]
    Rails.application.env_config["omniauth.auth"]       = auth
  end

  # Convenience for the failure-path spec.
  def mock_omniauth_failure(provider, reason = :invalid_credentials)
    OmniAuth.config.mock_auth[provider.to_sym] = reason
    Rails.application.env_config["devise.mapping"] = Devise.mappings[:user]
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers, type: :request

  # Reset OmniAuth state between examples so a mock or failure set in
  # one spec doesn't leak into the next.
  config.before(:each, type: :request) do
    OmniAuth.config.mock_auth.clear
    Rails.application.env_config.delete("omniauth.auth")
  end
end
