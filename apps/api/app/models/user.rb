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
  has_many :user_item_overrides, dependent: :destroy
  has_many :overridden_items, through: :user_item_overrides, source: :item
  has_many :restaurant_visits, dependent: :destroy
  has_many :favorite_restaurants, dependent: :destroy
  has_many :favorited_restaurants, through: :favorite_restaurants, source: :restaurant
  has_many :favorite_items, dependent: :destroy
  has_many :favorited_items, through: :favorite_items, source: :item
  # A chat transcript is personal — it goes with the account, unlike the
  # menu data a conversation may have contributed.
  has_many :conversations, dependent: :destroy

  # Legal remediation E2 — back-references with no ON DELETE rule at the
  # DB level. Account deletion would hit a foreign-key violation unless
  # these are nullified in Ruby first. The rows are part of the shared,
  # crowd-built menu graph (see docs/vision.md) — it shouldn't vanish
  # when one contributor leaves — so we drop the attribution, not the
  # row. The user's own personal records (reviews, profile, overrides,
  # visits) are destroyed above.
  has_many :ingestion_runs, inverse_of: :user, dependent: :nullify
  has_many :created_items, class_name: "Item", foreign_key: :created_by_user_id,
           inverse_of: :created_by_user, dependent: :nullify
  has_many :created_restaurants, class_name: "Restaurant", foreign_key: :created_by_user_id,
           inverse_of: :created_by_user, dependent: :nullify
  has_many :claimed_restaurants, class_name: "Restaurant", foreign_key: :claimed_by_user_id,
           inverse_of: :claimed_by_user, dependent: :nullify
  has_many :resolved_suggestions, class_name: "Suggestion", foreign_key: :resolved_by_user_id,
           inverse_of: :resolved_by_user, dependent: :nullify

  validates :handle, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9_]{3,30}\z/i }

  before_validation :ensure_jti, on: :create
  before_validation :assign_default_handle, on: :create
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

  # Legal remediation E9 — give accounts that didn't choose a handle a
  # NEUTRAL default. The handle is shown publicly (on reviews and at
  # /u/:handle), so it must not leak the email local-part the way the
  # old `default_handle_from_email` did ("jane.doe@…" → "jane_doe").
  # `diner_<random>` carries no PII; a user can still set a custom
  # handle at signup.
  def assign_default_handle
    return if handle.present?
    self.handle = loop do
      candidate = "diner_#{SecureRandom.hex(4)}"
      break candidate unless User.exists?(handle: candidate)
    end
  end

  def ensure_profile
    create_profile! unless profile
  end
end
