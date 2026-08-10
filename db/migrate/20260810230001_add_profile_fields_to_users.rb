class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :display_name, :string
    add_column :users, :locale, :string, null: false, default: :en.to_s
    add_column :users, :theme,  :string, null: false, default: "dark"
    add_column :users, :last_seen_at, :datetime
  end
end
