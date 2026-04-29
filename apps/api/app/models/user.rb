class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  # :confirmable + :trackable + :lockable land in Phase 4 (with the
  # mailer + privacy-respecting tracking). The schema's `current_sign_in_ip`
  # / `last_sign_in_ip` were intentionally omitted for privacy, which
  # makes :trackable crash on every login. JWT auth doesn't need email
  # confirmation, so :confirmable is also out for now.
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, :omniauthable,
         jwt_revocation_strategy: self,
         omniauth_providers: [:google_oauth2, :apple]

  has_one  :profile, class_name: "UserProfile", dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :suggestions, dependent: :nullify

  validates :handle, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9_]{3,30}\z/i }

  before_validation :ensure_jti, on: :create
  before_validation :default_handle_from_email, on: :create
  after_create_commit :ensure_profile

  # Find or create a user from an OmniAuth auth hash. Used by both the
  # google_oauth2 and apple callbacks. New users get an empty
  # UserProfile (via the after_create_commit callback) and are marked
  # confirmed — the OAuth provider has already verified the email.
  #
  # Apple's callback only returns the user's name on the very first
  # sign-in, so display_name is best-effort: filled when present, kept
  # otherwise.
  def self.from_omniauth(auth)
    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    # Use `blank?` rather than `||=` because the users.email column has
    # `default: ""` from Devise's migration generator — fresh records
    # come back with an empty string, which is truthy and would block
    # ||= from filling in the OAuth-provided email.
    user.email          = auth.info.email if user.email.blank?
    user.display_name   = auth.info.name  if user.display_name.blank?
    user.confirmed_at ||= Time.current

    # Devise needs *some* password for :database_authenticatable's
    # encrypted_password column to be set. Generate a random one on
    # first sign-in only — never rotate it on subsequent logins (the
    # `password` virtual is always nil on re-loaded records, so `||=`
    # would otherwise re-assign forever).
    if user.new_record?
      user.password              = Devise.friendly_token[0, 20]
      user.password_confirmation = user.password
    end

    user.save
    user
  end

  # OAuth-created users have a `provider` set; only ask Devise to
  # validate their password when they're plain email/password users
  # OR when they've explicitly set one.
  def password_required?
    return false if provider.present? && !encrypted_password_changed?
    super
  end

  private

  def ensure_jti
    self.jti ||= SecureRandom.uuid
  end

  def default_handle_from_email
    return if handle.present? || email.blank?
    base = email.split("@", 2).first.gsub(/[^a-z0-9_]/i, "_").downcase
    candidate = base
    suffix = 1
    candidate = "#{base}_#{suffix += 1}" while User.exists?(handle: candidate)
    self.handle = candidate
  end

  def ensure_profile
    create_profile! unless profile
  end
end
