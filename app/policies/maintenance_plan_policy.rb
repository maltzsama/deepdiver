class MaintenancePlanPolicy < ApplicationPolicy
  # Operators may trigger a run; pause/resume change the plan itself and stay
  # admin-only.
  def run?   = user&.admin? || user&.operator?
  def pause? = user&.admin?
  def resume? = user&.admin?
end
