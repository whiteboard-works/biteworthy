# frozen_string_literal: true

# Every statement a block sent to Postgres, so a spec can pin "once per
# turn, not once per round" as a property rather than as a benchmark
# somebody has to remember to re-run.
module SqlCapture
  def capture_sql
    seen = []
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      seen << payload[:sql].squish unless payload[:name].to_s == "SCHEMA"
    end
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end
end

RSpec.configure { |config| config.include SqlCapture }
