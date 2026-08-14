class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("DEVISE_MAILER_FROM", "no-reply@mail.bite-worthy.com")
  layout "mailer"
end
