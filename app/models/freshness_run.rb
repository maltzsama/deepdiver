class FreshnessRun < ApplicationRecord
  STATUSES = %w[pending running finished failed].freeze
end
