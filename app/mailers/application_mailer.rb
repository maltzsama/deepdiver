# Base class for all mailers. Configures the default sender and the "mailer"
# layout used by every outgoing email.
class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
end
