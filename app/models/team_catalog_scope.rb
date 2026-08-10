class TeamCatalogScope < ApplicationRecord
  belongs_to :team
  belongs_to :catalog

  validates :team_id, uniqueness: { scope: :catalog_id }
end
