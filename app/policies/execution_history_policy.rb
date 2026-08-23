# Governs access to execution history records.
class ExecutionHistoryPolicy < ApplicationPolicy
  # Who is allowed: admins and operators.
  def cancel? = user&.admin? || user&.operator?
end
