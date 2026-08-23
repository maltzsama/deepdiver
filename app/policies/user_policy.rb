# Governs access to user accounts and account management actions.
class UserPolicy < ApplicationPolicy
  # Who is allowed: admins.
  def index?      = user&.admin?
  # Who is allowed: admins.
  def new?        = user&.admin?
  # Who is allowed: admins.
  def create?     = user&.admin?
  # Who is allowed: admins.
  def update?     = user&.admin?
  # Who is allowed: admins, or the user themselves.
  def show?       = user&.admin? || record == user

  # Who is allowed: admins, but not on their own account.
  def suspend?    = user&.admin? && record != user
  # Who is allowed: admins, but not on their own account.
  def reactivate? = user&.admin? && record != user
end
