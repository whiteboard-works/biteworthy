class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  # :confirmable + :trackable + :lockable land in Phase 4 (with the
  # mailer + privacy-respecting tracking). The schema's `current_sign_in_ip`
  # / `last_sign_in_ip` were intentionally omitted for privacy, which
  # makes :trackable crash on every login. JWT auth doesn't need email
  # confirmation, so :confirmable is also out for now.
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  has_one  :profile, class_name: "UserProfile", dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :suggestions, dependent: :nullify

  validates :handle, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9_]{3,30}\z/i }

  before_validation :ensure_jti, on: :create
  before_validation :default_handle_from_email, on: :create
  after_create_commit :ensure_profile

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
