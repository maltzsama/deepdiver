class AddUserAndTeamAdministration < ActiveRecord::Migration[8.1]
  def change
    # Teams and memberships.
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
    add_index :team_memberships, [ :team_id, :user_id ], unique: true

    # Which catalogs a team controls. Empty scope means "all catalogs".
    create_table :team_catalog_scopes do |t|
      t.references :team, null: false, foreign_key: true
      t.references :catalog, null: false, foreign_key: true
      t.timestamps
    end
    add_index :team_catalog_scopes, [ :team_id, :catalog_id ], unique: true

    # User administration (invite / suspend lifecycle).
    add_column :users, :status, :string, null: false, default: "active"
    add_column :users, :invited_at, :datetime
    add_column :users, :invited_by_id, :bigint
    add_column :users, :suspended_at, :datetime
    add_column :users, :suspended_by_id, :bigint
    add_index :users, :status
    add_foreign_key :users, :users, column: :invited_by_id
    add_foreign_key :users, :users, column: :suspended_by_id

    # Role enum becomes viewer=0, operator=1, admin=2. Existing admins were
    # stored as 1, so shift them to 2 before the new app code reads the column.
    reversible do |dir|
      dir.up do
        execute "UPDATE users SET role = 2 WHERE role = 1"
      end
    end

    # Audit log of every manual role change.
    create_table :role_change_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :changed_by, null: false, foreign_key: { to_table: :users }
      t.integer :from_role, null: false
      t.integer :to_role, null: false
      t.string :reason
      t.timestamps
    end
  end
end
