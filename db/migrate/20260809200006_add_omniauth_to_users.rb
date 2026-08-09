class AddOmniauthToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid,      :string
    add_index  :users, %i[provider uid], unique: true

    # An IdP account has no local password.
    change_column_null :users, :encrypted_password, true
  end
end
