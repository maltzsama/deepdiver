# Governs access to activity records.
class ActivityPolicy < ApplicationPolicy
  # Who is allowed: all signed-in users.
  def show?    = true
  # Who is allowed: admins.
  def restart? = user&.admin?
  # Who is allowed: admins (destructive - tears the engine down).
  def hard_reset? = user&.admin?
  # Who is allowed: admins and operators.
  def cancel_query? = user&.admin? || user&.operator?
end
