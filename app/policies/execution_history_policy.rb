class ExecutionHistoryPolicy < ApplicationPolicy
  def cancel? = user&.admin?
end
