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

  factory :execution_history do
    maintenance_schedule
    status { "pending" }
    current_step { "start" }
  end
end
