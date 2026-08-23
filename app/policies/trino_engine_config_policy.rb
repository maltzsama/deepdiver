# Governs access to the engine config; every action is admin-only.
class TrinoEngineConfigPolicy < ApplicationPolicy
  # Who is allowed: admins.
  def show?   = user&.admin?
  # Who is allowed: admins.
  def update? = user&.admin?
end
