# frozen_string_literal: true

# The repo an error report's issue is in. A number alone names a
# stranger's issue once `GITHUB_ERROR_REPORTS_REPO` changes; with the repo
# beside it, a row whose issue is elsewhere starts over in the new target
# (`ErrorReports::GithubIssues#forget_foreign_issue`).
class AddIssueRepoToErrorReports < ActiveRecord::Migration[8.1]
  def change
    add_column :error_reports, :issue_repo, :string
  end
end
