# Grants a team access to a specific catalog, scoping which catalogs the team
# may act on.
class TeamCatalogScope < ApplicationRecord
  belongs_to :team
  belongs_to :catalog

  validates :team_id, uniqueness: { scope: :catalog_id }
end
