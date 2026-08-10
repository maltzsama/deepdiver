class IcebergTablePolicy < ApplicationPolicy
  def run_maintenance? = user&.admin?
end
