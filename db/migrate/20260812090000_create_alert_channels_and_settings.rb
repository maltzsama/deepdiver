class CreateAlertChannelsAndSettings < ActiveRecord::Migration[8.1]
  def change
    # Global alert transport configuration. SMTP server (Action Mailer) and
    # the single Slack webhook URL, plus the default sender address.
    create_table :alert_settings do |t|
      t.string :smtp_address
      t.integer :smtp_port
      t.string :smtp_user_name
      t.string :smtp_password
      t.string :smtp_from
      t.string :slack_webhook_url
      t.timestamps
    end

    # One alert channel = one configured destination. A channel may target
    # Slack (#channel), Email (address), or both; alerts are routed to every
    # enabled channel whose minimum severity the alert reaches.
    create_table :alert_channels do |t|
      t.string   :name, null: false
      t.string   :slack_channel
      t.string   :email_to
      t.string   :min_severity, null: false, default: "warning"
      t.integer  :cooldown_minutes, null: false, default: 60
      t.text     :message_template
      t.boolean  :enabled, null: false, default: true
      t.datetime :last_sent_at
      t.string   :last_error
      t.timestamps
      t.index :enabled
    end

    # Progressive freshness severity: tracks how badly a table is breaching,
    # escalating warning -> severe -> critical as the delay grows past 3h/6h/12h.
    add_column :table_freshness_slas, :severity, :string
  end
end
