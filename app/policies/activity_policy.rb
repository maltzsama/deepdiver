# Governs access to activity records.
class ActivityPolicy < ApplicationPolicy
  # Who is allowed: all signed-in users.
  def show?    = true
  # Who is allowed: admins.
  def restart? = user&.admin?
end
