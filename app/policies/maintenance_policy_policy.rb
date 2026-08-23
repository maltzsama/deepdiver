# Governs access to maintenance policies.
class MaintenancePolicyPolicy < ApplicationPolicy
  # Who is allowed: admins.
  def apply? = user&.admin?
end
