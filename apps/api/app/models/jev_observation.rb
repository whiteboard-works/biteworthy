# frozen_string_literal: true

# What Jev said, one row per call, whether the call decided something
# (`cuisine`) or only shadowed another model to be measured against it.
#
# This table exists because the first trial was measured from log lines
# and the API's logs do not outlive a deploy: 13 of 16 runs were gone
# before the decision was made. A shadow trial is a sample that has to
# accumulate across deploys, and a live call's failures and spend have to
# be visible after the fact, so both land here.
#
#   kind      what was asked: cuisine | hidden_wheat_shadow
#   subject   what the dishes belonged to (IngestionRun, Restaurant);
#             polymorphic, optional, nulled when the owner is deleted so
#             the dashboard's history keeps the spend
#   outcome   answered | partial (some answers missing) | failed (no answer)
#   agree     shadow trials only: Jev agreed with the model it shadows
#   details   the kind's own numbers and disagreements, bounded by the writer
#
# Reading it:
#   JevObservation.where(kind: "hidden_wheat_shadow").group(:agree).count
#   JevObservation.where(kind: "cuisine").group(:outcome).count
class JevObservation < ApplicationRecord
  KINDS    = %w[cuisine hidden_wheat_shadow].freeze
  OUTCOMES = %w[answered partial failed].freeze

  belongs_to :subject, polymorphic: true, optional: true

  validates :kind,    inclusion: { in: KINDS }
  validates :outcome, inclusion: { in: OUTCOMES }

  # An observation must never take down the thing it observes: a bad row
  # is logged and dropped, and the caller carries on. The savepoint is
  # what makes that true inside a caller's own transaction, where a
  # failed INSERT would otherwise poison every statement after it.
  def self.note(**attrs)
    transaction(requires_new: true) { create!(**attrs) }
  rescue StandardError => e
    Rails.logger.warn("[jev] observation not saved: #{e.class}: #{e.message.truncate(200)}")
    nil
  end
end
