# Governs access to maintenance plans.
class MaintenancePlanPolicy < ApplicationPolicy
  # Operators may trigger a run; pause/resume change the plan itself and stay
  # admin-only.
  # Who is allowed: admins and operators.
  def run?   = user&.admin? || user&.operator?
  # Who is allowed: admins.
  def pause? = user&.admin?
  # Who is allowed: admins.
  def resume? = user&.admin?
end
