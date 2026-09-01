# Governs access to user accounts and account management actions.
class UserPolicy < ApplicationPolicy
  # Who is allowed: admins.
  def index?      = user&.admin?
  # Who is allowed: admins.
  def new?        = user&.admin?
  # Who is allowed: admins.
  def create?     = user&.admin?
  # Who is allowed: admins, but not on their own account — self-demotion is an
  # irreversible lockout on single-admin installs (no user left can manage
  # accounts, and there is no UI path back).
  def update?     = user&.admin? && record != user
  # Who is allowed: admins, or the user themselves.
  def show?       = user&.admin? || record == user

  # Who is allowed: admins, but not on their own account.
  def suspend?    = user&.admin? && record != user
  # Who is allowed: admins, but not on their own account.
  def reactivate? = user&.admin? && record != user
end
