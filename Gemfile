source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Authentication [https://github.com/heartcombo/devise]
gem "devise"

# Cron parsing for maintenance_schedules dispatch [https://github.com/floraison/fugit]
gem "fugit"

# Kubernetes API client, used by the Trino scale up/down workers [https://github.com/abonas/kubeclient]
gem "kubeclient"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Solid Queue is our background job processor (database-backed, no Redis needed).
# See https://github.com/rails/solid_queue
gem "solid_queue"

# PostgreSQL only in production (on-prem, managed by CloudNativePG).
gem "pg", "~> 1.5", groups: %i[ production ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application as a Docker container consumed by the Helm chart
# (see infra/helm/lakedeepdiver).

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 2.0"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

gem "rspec-rails", "~> 8.0", groups: [ :development, :test ]

gem "factory_bot_rails", "~> 6.5", groups: [ :development, :test ]

gem "tailwindcss-rails", "~> 4.6"

gem "rails-controller-testing", "~> 1.0", groups: [ :development, :test ]

gem "omniauth_openid_connect", "~> 0.8.0"

gem "omniauth-rails_csrf_protection", "~> 2.0"

gem "bullet", "~> 8.1", groups: [ :development, :test ]

gem "solid_cable", "~> 4.0"

gem "pundit", "~> 2.5", require: "pundit"

gem "pagy", "~> 9.0"

# AWS STS for S3 temporary credentials (AssumeRole) used by Trino.
gem "aws-sdk-sts", "~> 1.0", require: false

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
