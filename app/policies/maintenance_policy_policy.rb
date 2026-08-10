class MaintenancePolicyPolicy < ApplicationPolicy
  def apply? = user&.admin?
end
