module AuthHelpers
  # Build an auth header for a user. Convenience for request specs that
  # need to hit a protected endpoint with a valid JWT.
  def auth_headers_for(user)
    token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
