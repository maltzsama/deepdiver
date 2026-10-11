# Team administration is an admin-only concern, not a self-service feature.
class TeamPolicy < ApplicationPolicy
  # Who is allowed: admins.
  def index?  = user&.admin?
  # Who is allowed: admins.
  def show?   = user&.admin?
  # Who is allowed: admins.
  def create? = user&.admin?
  # Who is allowed: admins.
  def new?    = user&.admin?
  # Who is allowed: admins.
  def update? = user&.admin?
  # Who is allowed: admins.
  def edit?   = user&.admin?
  # Who is allowed: admins.
  def destroy? = user&.admin?
end
