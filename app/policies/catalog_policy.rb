class CatalogPolicy < ApplicationPolicy
  # Sync/verify mutate catalog state and touch the engine; admin-only.
  def sync?   = user&.admin?
  def verify? = user&.admin?
end
