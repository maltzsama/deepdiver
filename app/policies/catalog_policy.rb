# Governs access to data catalogs.
class CatalogPolicy < ApplicationPolicy
  # Sync/verify mutate catalog state and touch the engine; admin-only.
  # Who is allowed: admins.
  def sync?   = user&.admin?
  # Who is allowed: admins.
  def verify? = user&.admin?
end
