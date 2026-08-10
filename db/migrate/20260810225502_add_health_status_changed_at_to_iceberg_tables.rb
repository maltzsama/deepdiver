class AddHealthStatusChangedAtToIcebergTables < ActiveRecord::Migration[8.1]
  def change
    # Quando a tabela ENTROU no estado atual de saúde. Permite ordenar a
    # triagem por "o que quebrou mais recentemente".
    add_column :iceberg_tables, :health_status_changed_at, :datetime
    add_index  :iceberg_tables, %i[health_status health_status_changed_at]
  end
end
