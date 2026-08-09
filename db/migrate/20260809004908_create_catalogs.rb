# frozen_string_literal: true

class CreateCatalogs < ActiveRecord::Migration[8.1]
  def change
    create_table :catalogs do |t|
      t.string :name, null: false
      t.string :catalog_type, null: false
      t.string :endpoint, null: false
      t.json :properties, default: {}

      t.timestamps
    end

    add_index :catalogs, :name, unique: true
  end
end
