# Governs access to execution history records.
class ExecutionHistoryPolicy < ApplicationPolicy
  # Who is allowed: admins.
  def cancel? = user&.admin?
end
