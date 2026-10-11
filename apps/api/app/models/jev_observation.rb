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
#   kind      what was asked: cuisine | hidden_wheat_shadow | grounding_shadow
#   subject   what the dishes or answer belonged to (IngestionRun,
#             Restaurant, Conversation); polymorphic, optional
#   outcome   answered | partial (some answers missing) | failed (no answer)
#   agree     shadow trials only: Jev agreed with the model it shadows
#   details   the kind's own numbers and disagreements, bounded by the writer
#
# Reading it:
#   JevObservation.where(kind: "grounding_shadow").group(:agree).count
#   JevObservation.where(kind: "cuisine").group(:outcome).count
class JevObservation < ApplicationRecord
  KINDS    = %w[cuisine hidden_wheat_shadow grounding_shadow].freeze
  OUTCOMES = %w[answered partial failed].freeze

  belongs_to :subject, polymorphic: true, optional: true

  validates :kind,    inclusion: { in: KINDS }
  validates :outcome, inclusion: { in: OUTCOMES }

  # An observation must never take down the thing it observes: a bad row
  # is logged and dropped, and the caller carries on.
  def self.note(**attrs)
    create!(**attrs)
  rescue StandardError => e
    Rails.logger.warn("[jev] observation not saved: #{e.class}: #{e.message.truncate(200)}")
    nil
  end
end
