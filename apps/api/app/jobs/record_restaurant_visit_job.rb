# Phase 4.8 — record a "user opened this restaurant today" row.
#
# Enqueued (best-effort, fire-and-forget) by the items endpoint when
# an authenticated user fetches a restaurant's menu. The job upserts
# one row per (user, restaurant, day) — the unique index in the
# migration makes that race-safe.
#
# Counts reflect the LAST visit of the day (overwrite, not sum). Fine
# for the use case ("see what I saw"). The history list reads from
# this table; nothing else does.
#
# Failure semantics: this is best-effort telemetry. If the enqueue
# fails or the job raises, swallow it — we never want to leak a
# request error because we couldn't record a visit.
class RecordRestaurantVisitJob < ApplicationJob
  queue_as :default

  def perform(user_id, restaurant_id, items_visible_count, items_hidden_count, viewed_on_iso = nil)
    viewed_on = viewed_on_iso ? Date.iso8601(viewed_on_iso) : Date.current

    visit = RestaurantVisit.find_or_initialize_by(
      user_id: user_id,
      restaurant_id: restaurant_id,
      viewed_on: viewed_on
    )
    visit.items_visible_count = items_visible_count
    visit.items_hidden_count  = items_hidden_count
    visit.save!
  rescue ActiveRecord::RecordNotUnique
    # Lost the upsert race with another worker — retry once and let
    # find_or_initialize_by find the row this time.
    retry
  rescue ActiveRecord::InvalidForeignKey
    # User or restaurant deleted between request + job execution.
    # Best-effort: drop silently.
  end
end
