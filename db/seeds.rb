# Seed data for a local/development deployment.
if Rails.env.development? || ENV["SEED_DEMO"]
  admin = User.find_or_create_by!(email: "admin@example.com") do |user|
    user.password = "changeme!"
    user.role = "admin"
  end

  catalog = Catalog.find_or_create_by!(name: "analytics") do |c|
    c.catalog_type = "nessie"
    c.endpoint = "http://nessie.default.svc.cluster.local:19120/api/v1"
    c.trino_catalog_name = "analytics"
  end

  table = catalog.iceberg_tables.find_or_create_by!(namespace: "reporting", name: "dwd_orders") do |t|
    t.health_score = 42
    t.health_status = "warning"
  end

  table.maintenance_schedules.find_or_create_by!(operation: "optimize") do |s|
    s.cron = "0 3 * * *"
    s.config = { "file_size_threshold" => "128MB" }
  end
end

puts "Seeded #{User.count} users, #{Catalog.count} catalogs, #{IcebergTable.count} tables."
