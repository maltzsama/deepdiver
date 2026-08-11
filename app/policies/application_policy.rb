# Base policy shared by every resource. Read actions are open to all signed-in
# users; every mutation is admin-only unless overridden in a subclass.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # Who is allowed: all signed-in users.
  def index?    = true
  # Who is allowed: all signed-in users.
  def show?     = true
  # Who is allowed: admins.
  def new?      = user&.admin?
  # Who is allowed: admins.
  def create?   = user&.admin?
  # Who is allowed: admins.
  def edit?     = user&.admin?
  # Who is allowed: admins.
  def update?   = user&.admin?
  # Who is allowed: admins.
  def destroy?  = user&.admin?

  # Scopes the records a user may access; the default exposes all records.
  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.all
    end

    private

    attr_reader :user, :scope
  end
end
