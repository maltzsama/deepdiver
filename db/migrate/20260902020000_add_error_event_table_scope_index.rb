class AddErrorEventTableScopeIndex < ActiveRecord::Migration[8.0]
  def change
    # table_events runs on every table detail page load; the scope is now
    # catalog_id + schema + table + status (see #210).
    add_index :error_events, [ :catalog_id, :schema, :table, :status ],
              name: "index_error_events_on_catalog_schema_table_status"
  end
end
