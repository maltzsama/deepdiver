FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password" }
    role { "viewer" }

    trait :admin do
      role { "admin" }
    end

    trait :operator do
      role { "operator" }
    end

    trait :invited do
      status { "invited" }
    end

    trait :suspended do
      status { "suspended" }
    end

    trait :sso do
      provider { "openid_connect" }
      uid { "https://idp.example.com/user-1" }
    end
  end

  factory :team do
    sequence(:name) { |n| "Team #{n}" }
  end

  factory :team_membership do
    team
    user
  end

  factory :team_catalog_scope do
    team
    catalog
  end

  factory :role_change_log do
    user
    association :changed_by, factory: :user
    from_role { 0 }
    to_role { 0 }
  end

  factory :catalog do
    sequence(:name) { |n| "catalog-#{n}" }
    catalog_type { "nessie" }
    endpoint { "http://nessie:19120/api/v1" }

    factory :polaris_catalog do
      catalog_type { "polaris" }
      endpoint { "http://polaris:8181" }
    end
  end

  factory :catalog_credential do
    catalog
    auth_method { "none" }
  end

  factory :iceberg_table do
    catalog
    sequence(:name) { |n| "table-#{n}" }
    namespace { "reporting" }
  end

  factory :maintenance_schedule do
    iceberg_table
    operation { "optimize" }
    cron { "0 3 * * *" }
    is_paused { false }
    config { {} }
  end

  factory :table_freshness_sla do
    iceberg_table
    enabled { true }
    timestamp_column { "load_timestamp" }
    timestamp_type { "timestamp_tz" }
    source_timezone { "UTC" }
    partition_column { "dt" }
    partition_lookback { 7 }
    sla_minutes { 120 }
    warning_at_percent { 80 }
    warning_after_minutes { 180 }
    severe_after_minutes { 360 }
    critical_after_minutes { 720 }
    slack_channel { "#alerts" }
  end

  factory :freshness_run do
    status { "pending" }
  end

  factory :freshness_check do
    iceberg_table
    checked_at { Time.current }
    status { "ok" }
    delay_seconds { 0 }
    sla_minutes { 120 }
  end

  factory :maintenance_plan do
    iceberg_table
    cron { "0 3 * * *" }
    is_paused { false }
    consecutive_failures { 0 }
    auto_pause_after { 3 }

    trait :with_all_steps do
      after(:create) do |plan|
        MaintenancePlan::CANONICAL_ORDER.each_with_index do |operation, index|
          plan.maintenance_steps.create!(operation: operation, position: index, config: {})
        end
      end
    end
  end

  factory :maintenance_step do
    maintenance_plan
    operation { "optimize" }
    position { 0 }
    enabled { true }
    config { {} }
  end

  factory :execution_step do
    execution_history
    operation { "optimize" }
    status { "pending" }
  end

  factory :execution_history do
    iceberg_table
    maintenance_schedule { nil }
    maintenance_plan { nil }
    status { "running" }
    current_step { "start" }
  end

  factory :alert_setting do
    smtp_address { "smtp.example.com" }
    smtp_port { 587 }
    smtp_user_name { "alerts" }
    smtp_password { "secret" }
    smtp_from { "alerts@example.com" }
    slack_webhook_url { "https://hooks.slack.com/services/T000/B000/XXXX" }
  end
end
