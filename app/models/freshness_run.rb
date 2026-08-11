# One sweep across the tracked tables to evaluate freshness, tracking the
# run's overall status and timing.
class FreshnessRun < ApplicationRecord
  STATUSES = %w[pending running finished failed].freeze
end
