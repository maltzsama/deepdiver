class MaintenanceStep < ApplicationRecord
  belongs_to :maintenance_plan

  validates :operation, presence: true, inclusion: { in: MaintenancePlan::CANONICAL_ORDER }
  validates :position, presence: true
end
