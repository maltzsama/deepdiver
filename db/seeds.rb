# Seed data for a local/development deployment.
if Rails.env.development? || ENV["SEED_DEMO"]
  admin = User.find_or_create_by!(email: "admin@example.com") do |user|
    user.password = "changeme!"
    user.role = "admin"
  end

  catalog = Catalog.find_or_create_by!(name: "analytics") do |c|
    c.catalog_type = "nessie"
    c.endpoint = "http://nessie.default.svc.cluster.local:19120/api/v1"
  end

  table = catalog.iceberg_tables.find_or_create_by!(namespace: "reporting", name: "dwd_orders") do |t|
    t.health_score = 42
    t.health_status = "warning"
  end

end

# Seed the global alert transport from env vars so the app works out of the
# box without visiting the admin panel. Each table's SLA picks its own Slack
# #channel and email recipients from this transport.
alert_settings = AlertSetting.instance
alert_settings.update!(
  smtp_address: ENV["SMTP_ADDRESS"].presence,
  smtp_port: ENV["SMTP_PORT"].presence,
  smtp_user_name: ENV["SMTP_USERNAME"].presence,
  smtp_password: ENV["SMTP_PASSWORD"].presence,
  smtp_from: ENV["SMTP_FROM"].presence || alert_settings.smtp_from,
  slack_webhook_url: ENV["SLACK_WEBHOOK_URL"].presence || alert_settings.slack_webhook_url
)

puts "Seeded #{User.count} users, #{Catalog.count} catalogs, #{IcebergTable.count} tables."

if ENV["BOOTSTRAP_ADMIN_EMAIL"].present?
  user = User.find_or_initialize_by(email: ENV.fetch("BOOTSTRAP_ADMIN_EMAIL"))
  user.password ||= ENV.fetch("BOOTSTRAP_ADMIN_PASSWORD")
  user.role = :admin
  user.save!
  puts "admin ensured: #{user.email}"
end
