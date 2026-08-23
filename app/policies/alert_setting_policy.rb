# Governs access to the global alert settings; every action is admin-only.
class AlertSettingPolicy < ApplicationPolicy
  # Who is allowed: admins.
  def show?   = user&.admin?
  # Who is allowed: admins.
  def edit?   = user&.admin?
  # Who is allowed: admins.
  def update? = user&.admin?
end
