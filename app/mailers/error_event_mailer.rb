# Sends error-event assignment notifications to the assigned users.
class ErrorEventMailer < ApplicationMailer
  # Notifies a user that an error event was assigned to them.
  #
  # @param to [String] the assignee email address
  # @param event [ErrorEvent] the assigned event
  # @param assigned_by [User] who performed the assignment
  def assignment_notification(to:, event:, assigned_by:)
    @event = event
    @assigned_by = assigned_by
    setting = AlertSetting.instance
    mail(
      to: to,
      subject: subject,
      from: setting.from_address,
      delivery_method_settings: alert_delivery_settings
    ) do |format|
      format.text { render plain: body_text }
    end
  end

  private

  # Email subject line identifying the failing operation and location.
  def subject
    t("error_event_mailer.assignment.subject", operation: @event.operation,
                                               where: where_label)
  end

  # Plain-text body with the full error message and a link to the event.
  def body_text
    <<~TEXT
      #{t("error_event_mailer.assignment.greeting")}
      #{t("error_event_mailer.assignment.intro", assigned_by: @assigned_by.email)}

      #{t("error_event_mailer.assignment.operation")}: #{@event.operation}
      #{t("error_event_mailer.assignment.where")}: #{where_label}
      #{t("error_event_mailer.assignment.message")}: #{@event.message}
      #{t("error_event_mailer.assignment.error_class")}: #{@event.error_class}
      #{t("error_event_mailer.assignment.occurrences")}: #{@event.occurrence_count}

      #{error_event_url(@event)}
    TEXT
  end

  # Human-readable location: catalog + schema.table when known.
  def where_label
    [ @event.catalog&.name, [ @event.schema, @event.table ].reject(&:blank?).join(".") ]
      .compact.reject(&:blank?).join(" / ")
  end
end
