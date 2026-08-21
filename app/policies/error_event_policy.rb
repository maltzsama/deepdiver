# Governs access to error events surfaced by the engine.
class ErrorEventPolicy < ApplicationPolicy
  def index? = true
  def show?  = true
end
