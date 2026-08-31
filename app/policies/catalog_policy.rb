# Governs access to data catalogs.
class CatalogPolicy < ApplicationPolicy
  # Sync/verify mutate catalog state and touch the engine; admin-only.
  # Who is allowed: admins.
  def sync?   = user&.admin?
  def verify? = user&.admin?
  def verify_draft? = user&.admin?
end
