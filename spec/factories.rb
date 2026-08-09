FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password" }
    role { "viewer" }

    trait :admin do
      role { "admin" }
    end
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
  end

  factory :freshness_run do
    status { "pending" }
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
end
