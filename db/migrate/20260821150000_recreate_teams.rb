class RecreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
    add_index :teams, :name, unique: true

    create_table :team_memberships do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :team_memberships, %i[team_id user_id], unique: true
  end
end
