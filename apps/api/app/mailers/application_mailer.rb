class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("DEVISE_MAILER_FROM", "no-reply@bite-worthy.com")
  layout "mailer"
end
