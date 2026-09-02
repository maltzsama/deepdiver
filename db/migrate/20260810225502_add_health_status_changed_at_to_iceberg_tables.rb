class AddHealthStatusChangedAtToIcebergTables < ActiveRecord::Migration[8.1]
  def change
    # When the table ENTERED its current health state. Lets triage be ordered
    # by "what broke most recently".
    add_column :iceberg_tables, :health_status_changed_at, :datetime
    add_index  :iceberg_tables, %i[health_status health_status_changed_at]
  end
end
