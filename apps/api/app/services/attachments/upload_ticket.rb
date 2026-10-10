# frozen_string_literal: true

module Attachments
  # A short-lived credential good for one thing: a browser sending a file
  # to POST /api/v1/attachments.
  #
  # The web session is an HttpOnly cookie, so the browser cannot present
  # the JWT itself, and the upload used to pass through a Next.js route
  # whose body limit (4.5 MB on Vercel) sat below the API's own. Now the
  # proxy mints this ticket with the session and the browser sends the
  # bytes straight to Rails with it. A ticket names its user, expires in
  # minutes, and opens nothing else — a leaked one uploads a file, it
  # does not read an account.
  class UploadTicket
    TTL     = 10.minutes
    PURPOSE = :attachment_upload

    def self.issue(user)
      verifier.generate({ "user_id" => user.id }, expires_in: TTL, purpose: PURPOSE)
    end

    # The user a ticket names, or nil for a missing, forged, or expired one.
    def self.user_for(ticket)
      return nil if ticket.blank?

      payload = verifier.verified(ticket, purpose: PURPOSE)
      payload && User.find_by(id: payload["user_id"])
    end

    def self.verifier = Rails.application.message_verifier("attachments.upload_ticket")
  end
end
