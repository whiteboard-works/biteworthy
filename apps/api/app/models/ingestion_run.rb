class IngestionRun < ApplicationRecord
  INPUT_KINDS = %w[photo url pdf].freeze
  STATUSES    = %w[queued extracting resolving staged published failed].freeze

  # The pipeline marches forward through these states. `failed` is
  # reachable from any state but isn't in this map. The two stage
  # entries that have a job_for value get a Solid Queue job kicked off
  # automatically when transition_to! lands the run there.
  #
  # Job class names use safe_constantize so this model doesn't depend
  # on the job classes existing yet — Phase 2.3 / 2.4 add them and
  # the dispatch starts firing without further changes here.
  NEXT_STATE = {
    "queued"     => "extracting",
    "extracting" => "resolving",
    "resolving"  => "staged",
    "staged"     => "published"
  }.freeze

  JOB_FOR = {
    "extracting" => "ExtractMenuJob",
    "resolving"  => "ResolveIngredientsJob"
  }.freeze

  class InvalidTransition < StandardError; end

  belongs_to :user, optional: true
  belongs_to :restaurant, optional: true
  has_many :ingestion_items, dependent: :destroy

  # The source artifact(s) we're extracting from. Multi-page menu
  # photos arrive as an array of attachments; URL/PDF runs typically
  # have a single attachment that the URL fetcher saved.
  has_many_attached :inputs

  validates :input_kind, inclusion: { in: INPUT_KINDS }
  validates :status,     inclusion: { in: STATUSES }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  # Move the run to `new_status` and record the entry timestamp in
  # state_history (only the first entry per state — re-running the
  # same transition is a no-op but timestamps don't get clobbered).
  # Fires the next-stage Solid Queue job when one is registered for
  # the new state.
  #
  # Raises InvalidTransition for forward-moves that aren't in the
  # NEXT_STATE map (e.g., trying to jump from queued → published).
  # `:failed` is always allowed.
  def transition_to!(new_status)
    new_status = new_status.to_s
    raise ArgumentError, "Unknown status: #{new_status.inspect}" unless STATUSES.include?(new_status)
    return self if status == new_status

    unless new_status == "failed" || NEXT_STATE[status] == new_status
      raise InvalidTransition,
            "Cannot transition IngestionRun ##{id} from #{status.inspect} to #{new_status.inspect}"
    end

    transaction do
      record_state_entry!(new_status)
      update!(status: new_status)
      enqueue_next_job!(new_status)
    end
    self
  end

  # Convenience for the failure path — records the message so
  # operators can see what went wrong from /admin or the dashboard.
  def fail!(message)
    transaction do
      assign_attributes(failure_message: message.to_s.truncate(2_000))
      transition_to!(:failed)
    end
    self
  end

  private

  def record_state_entry!(new_status)
    return if state_history.key?(new_status) # idempotent — first entry wins

    history = state_history.merge(new_status => Time.current.utc.iso8601)
    self.state_history = history
  end

  def enqueue_next_job!(new_status)
    job_name  = JOB_FOR[new_status]
    job_class = job_name&.safe_constantize
    job_class&.perform_later(id)
  end
end
