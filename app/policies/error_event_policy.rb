class ErrorEventPolicy < ApplicationPolicy
  def index? = true
  def show?  = true
  # Acknowledging / resolving mutates the error surface: operators can keep up
  # with it, not only admins.
  def acknowledge? = user&.admin? || user&.operator?
  def resolve? = user&.admin? || user&.operator?
end
