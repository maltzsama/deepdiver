# Governs access to Iceberg tables in the catalog.
class IcebergTablePolicy < ApplicationPolicy
  # Operators may trigger maintenance on a table; only admins manage plans.
  # Who is allowed: admins and operators.
  def run_maintenance? = user&.admin? || user&.operator?
  def sync_table? = user&.admin? || user&.operator?
end
