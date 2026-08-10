class UserPolicy < ApplicationPolicy
  def index?      = user&.admin?
  def new?        = user&.admin?
  def create?     = user&.admin?
  def update?     = user&.admin?
  def show?       = user&.admin? || record == user

  def suspend?    = user&.admin? && record != user
  def reactivate? = user&.admin? && record != user
end
