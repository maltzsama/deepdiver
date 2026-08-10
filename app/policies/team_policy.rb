class TeamPolicy < ApplicationPolicy
  def index?   = user&.admin?
  def new?     = user&.admin?
  def create?  = user&.admin?
  def edit?    = user&.admin?
  def update?  = user&.admin?
  def destroy? = user&.admin?
end
