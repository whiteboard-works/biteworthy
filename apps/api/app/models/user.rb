class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :trackable

  has_one  :profile, class_name: "UserProfile", dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :suggestions, dependent: :nullify

  validates :handle, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9_]{3,30}\z/i }

  before_validation :ensure_jti, on: :create

  private

  def ensure_jti
    self.jti ||= SecureRandom.uuid
  end
end
