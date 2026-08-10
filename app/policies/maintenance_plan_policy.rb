class MaintenancePlanPolicy < ApplicationPolicy
  def run?   = user&.admin?
  def pause? = user&.admin?
  def resume? = user&.admin?
end
