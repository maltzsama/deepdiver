class DropTeams < ActiveRecord::Migration[8.1]
  def change
    drop_table :team_catalog_scopes
    drop_table :team_memberships
    drop_table :teams
  end
end
