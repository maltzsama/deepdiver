class IcebergTablePolicy < ApplicationPolicy
  # Operators may trigger maintenance on a table; only admins manage plans.
  def run_maintenance? = user&.admin? || user&.operator?
end
