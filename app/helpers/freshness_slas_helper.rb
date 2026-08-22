module FreshnessSlasHelper
  # [name, iceberg_type] pairs from the schema captured at the last sync,
  # used as column suggestions on the SLA form. Empty on any malformed or
  # missing payload - suggestions are a convenience, never a requirement.
  def synced_schema_fields(table)
    schema = table.schema_json
    schema = schema.first if schema.is_a?(Array)
    fields = schema.is_a?(Hash) ? schema["fields"] : []
    Array(fields).filter_map do |field|
      next unless field.is_a?(Hash) && field["name"].present?

      [ field["name"], field["type"].to_s ]
    end
  rescue StandardError
    []
  end
end
