# Legal remediation E5 — visit-history retention backstop.
#
# Account deletion (E2) destroys a user's restaurant_visits immediately
# via dependent: :destroy, well inside the Privacy Policy's "removed
# from active systems within 30 days" window. This recurring job is the
# belt-and-suspenders that backs the "fully purged within 12 months"
# guarantee: it deletes any visit row that has lost its owning user —
# the kind of orphan a bulk SQL operation, a restore-from-backup, or a
# future schema change could leave behind even though the foreign key
# normally prevents it.
#
# There is intentionally NO rolling age cap while an account is open —
# visit history is kept for the account's lifetime (founder decision).
# This job only removes rows whose user is already gone.
class PurgeOrphanedRestaurantVisitsJob < ApplicationJob
  queue_as :default

  def perform
    purged = RestaurantVisit
             .where("NOT EXISTS (SELECT 1 FROM users WHERE users.id = restaurant_visits.user_id)")
             .delete_all
    Rails.logger.info("[retention] purged #{purged} orphaned restaurant_visits") if purged.positive?
    purged
  end
end
