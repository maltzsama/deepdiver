# Governs access to maintenance policies.
class MaintenancePolicyPolicy < ApplicationPolicy
  # Who is allowed: admins.
  def apply? = user&.admin?

  # Detaching a plan from a policy is admin-only, like apply.
  def detach? = user&.admin?
end
