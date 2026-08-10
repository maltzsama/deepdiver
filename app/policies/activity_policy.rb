class ActivityPolicy < ApplicationPolicy
  def show?    = true
  def restart? = user&.admin?
end
