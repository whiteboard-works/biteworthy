class UserItemOverride < ApplicationRecord
  # Phase 4.2 — persistent "show anyway" / "never hide this dish"
  # override. Survives logout/login (session-only equivalent lives
  # in the React Native + Next clients per Phase 3.4).
  #
  # `never_hide: true` is currently the only mode. The column is here
  # rather than encoded as presence-of-row so future modes can land
  # without a migration.

  belongs_to :user
  belongs_to :item

  validates :user_id, uniqueness: { scope: :item_id }
end
