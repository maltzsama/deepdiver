# Governs access to error events surfaced by the engine.
class ErrorEventPolicy < ApplicationPolicy
  # Who is allowed: all signed-in users.
  def index? = true
  # Who is allowed: all signed-in users.
  def show?  = true
  # Acknowledging / resolving mutates the error surface: operators can keep up
  # with it, not only admins.
  # Who is allowed: admins and operators.
  def acknowledge? = user&.admin? || user&.operator?
  # Who is allowed: admins and operators.
  def resolve? = user&.admin? || user&.operator?
end
