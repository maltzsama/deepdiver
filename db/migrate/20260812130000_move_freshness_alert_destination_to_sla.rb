class MoveFreshnessAlertDestinationToSla < ActiveRecord::Migration[8.1]
  def change
    # The alert destination is configured per table, on the SLA, right next to
    # the severity bands: which Slack #channel and which email recipients get
    # the freshness alerts. The global AlertChannel concept is dropped.
    add_column :table_freshness_slas, :slack_channel, :string
    add_column :table_freshness_slas, :email_to, :string

    drop_table :alert_channels
  end
end
