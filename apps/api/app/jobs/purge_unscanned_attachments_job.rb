# frozen_string_literal: true

# Uploads that were never scanned.
#
# `POST /api/v1/attachments` writes a blob and hands back a signed id so
# the bytes never enter the agent's context. If the person then closes the
# tab — or the model never calls `start_menu_scan` — that blob is attached
# to nothing and stays in storage forever. Nothing else in the app deletes
# it, because nothing else knows it exists.
#
# `unattached` is a safe signal here rather than a guess, and it is worth
# writing down why, because the failure mode is deleting someone's menu
# photo. Two facts, both checkable:
#
#   * A scanned upload becomes attached — `IngestionRun has_many_attached
#     :inputs`, written by `run.inputs.attach`.
#   * `AttachmentsController` is the **only** place in the app that creates
#     a detached blob. Everything else goes through `attach(io:)`, which
#     creates the blob already attached.
#
# So an unattached blob past the grace window can only be a chat upload
# nobody ever scanned.
#
# The age floor is the whole safety story. An upload that is seconds old
# is almost certainly mid-flight — the person is still typing the message
# that will reference it — so a day of grace separates "abandoned" from
# "in progress" without needing to track intent.
class PurgeUnscannedAttachmentsJob < ApplicationJob
  queue_as :default

  GRACE_HOURS_DEFAULT = 24
  # Bounds the enqueue burst. A backlog drains over successive runs rather
  # than flooding the queue in one go.
  MAX_PER_RUN = 500

  def perform
    cutoff = grace_hours.hours.ago
    purged = 0

    ActiveStorage::Blob.unattached
                       .where(created_at: ...cutoff)
                       .order(:created_at)
                       .limit(MAX_PER_RUN)
                       .find_each do |blob|
      # purge_later so a slow storage backend cannot stall the sweep; the
      # row and the file both go.
      blob.purge_later
      purged += 1
    end

    Rails.logger.info("[retention] purged #{purged} unscanned attachments") if purged.positive?
    purged
  end

  private

  def grace_hours
    Integer(ENV.fetch("ATTACHMENT_PURGE_GRACE_HOURS", GRACE_HOURS_DEFAULT))
  end
end
