# Governs access to error events surfaced by the engine.
class ErrorEventPolicy < ApplicationPolicy
  # Who is allowed: all signed-in users.
  def index? = true
  # Who is allowed: all signed-in users.
  def show?  = true
  # Acknowledging and assigning mutate the error surface workflow:
  # admins and operators participate, viewers do not.
  # Who is allowed: admins and operators.
  def acknowledge? = user&.admin? || user&.operator?
  # Who is allowed: admins and operators.
  def assign? = user&.admin? || user&.operator?
  # Who is allowed: admins and operators.
  def resolve? = user&.admin? || user&.operator?
end
