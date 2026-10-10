# frozen_string_literal: true

require "rails_helper"

# The wiring, not the behaviour: `config/initializers/error_reports.rb`
# is the only thing that makes `Rails.error.report` do anything at all,
# and nothing else would notice it going missing.
RSpec.describe "Rails.error subscription" do
  include ActiveJob::TestHelper

  it "turns a reported error into a filing job" do
    expect { Rails.error.report(RuntimeError.new("wired"), handled: true, context: { component: "spec" }) }
      .to have_enqueued_job(ErrorReports::FileIssueJob)
      .with(hash_including("title" => "[spec] RuntimeError: wired"))
  end
end
