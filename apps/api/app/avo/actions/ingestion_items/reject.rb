class Avo::Actions::IngestionItems::Reject < Avo::BaseAction
  self.name = "Reject (do not promote)"
  self.message = "Mark the selected ingestion item(s) as rejected. They stay in the audit log but no Item is materialized."
  self.confirm_button_label = "Reject"

  def handle(query:, **)
    self.class.reject_all(query)
    succeed "Rejected #{query.size} item(s)."
  end

  # Pure logic; same reason as Accept#accept_all (testable without
  # the Avo controller lifecycle).
  def self.reject_all(items)
    items.each do |ingestion_item|
      next if ingestion_item.rejected?

      ingestion_item.update!(decision: "rejected", decided_at: Time.current)
    end

    # Same publication-threshold check as Accept — rejecting also
    # moves the "decided" denominator forward.
    items.map(&:ingestion_run).uniq.each(&:maybe_publish!)
  end
end
