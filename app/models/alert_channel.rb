# A configured alert destination. Each channel targets Slack, Email, or both,
# and only receives alerts whose severity is at or above its minimum. Alerts
# are routed through AlertChannelNotifier, which enforces the channel's
# cooldown so a stuck table does not page the same channel every hour.
class AlertChannel < ApplicationRecord
  SEVERITIES = %w[warning severe critical].freeze
  SEVERITY_LEVEL = { "warning" => 1, "severe" => 2, "critical" => 3 }.freeze

  validates :name, presence: true
  validates :min_severity, inclusion: { in: SEVERITIES }
  validates :cooldown_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :must_have_a_destination

  scope :enabled, -> { where(enabled: true) }

  # Whether the channel may receive an alert of the given severity.
  #
  # @param severity [String, nil] the alert severity ("warning"/"severe"/"critical")
  # @return [Boolean] true when the channel's minimum severity is met
  def receives?(severity)
    SEVERITY_LEVEL.fetch(severity.to_s, 0) >= SEVERITY_LEVEL.fetch(min_severity, 1)
  end

  # Whether the channel is inside its cooldown window since the last send.
  #
  # @return [Boolean] true when the channel should skip the alert
  def cooling_down?
    last_sent_at.present? && last_sent_at > cooldown_minutes.minutes.ago
  end

  # Whether the channel has a destination to send to.
  #
  # @return [Boolean]
  def configured?
    slack_channel.present? || email_to.present?
  end

  private

  # At least one of Slack or Email must be set, otherwise the channel does
  # nothing and is just noise in the admin list.
  def must_have_a_destination
    errors.add(:base, :no_destination) if slack_channel.blank? && email_to.blank?
  end
end
