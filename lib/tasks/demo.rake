namespace :demo do
  desc "Create per-table freshness SLAs for the demo environment (idempotent). " \
       "The stalest active table gets a tight 5-minute SLA so it breaches on " \
       "the next probe; one healthy table gets a generous 24h SLA for " \
       "contrast. Tables without an SLA stay without one - that is a " \
       "legitimate state. Existing SLAs are never modified."
  task freshness_sla: :environment do
    tables = IcebergTable.active.order(Arel.sql("last_data_update ASC NULLS LAST")).to_a
    abort "demo:freshness_sla: no synced tables - run a catalog sync first" if tables.empty?

    created = []

    # 1) The late one: oldest data + tight budget.
    stale = tables.first
    created << ensure_sla!(stale, sla_minutes: 5)

    # 2) The contrast: a second table, generous budget, expected on-track.
    if (healthy = tables.second)
      created << ensure_sla!(healthy, sla_minutes: 1440)
    end

    if created.any?
      puts "Created #{created.size} SLA(s): #{created.join(', ')}"
      MaintenanceOrchestrator.enqueue_freshness_sweep
      puts "Freshness sweep enqueued."
    else
      puts "SLAs already in place; nothing to do."
    end
  end
end

# Creates the SLA only when absent - operator edits always win over the demo.
def ensure_sla!(table, sla_minutes:)
  return nil if table.table_freshness_sla.present?

  TableFreshnessSla.create!(
    iceberg_table: table,
    enabled: true,
    sla_minutes: sla_minutes,
    timestamp_column: demo_timestamp_column(table),
    timestamp_type: demo_timestamp_type(table),
    source_timezone: "UTC",
    warning_at_percent: 80,
    warning_after_minutes: (sla_minutes * 2).to_i,
    severe_after_minutes: (sla_minutes * 6).to_i,
    critical_after_minutes: (sla_minutes * 12).to_i
  )
  "#{table.namespace}.#{table.name} (#{sla_minutes} min)"
end

# Picks the first timestamp-ish column from the schema captured by the last
# sync; raises when none exists because probing without one is impossible.
def demo_timestamp_column(table)
  column = timestamp_columns(table).first
  abort <<~MSG if column.nil?
    demo:freshness_sla: #{table.namespace}.#{table.name} has no timestamp/date column
    in its persisted schema - configure its SLA manually via the UI.
  MSG

  column["name"]
end

# Maps the Iceberg primitive type to what FreshnessProbe understands.
def demo_timestamp_type(table)
  type = timestamp_columns(table).first.to_h.fetch("type")
  case type
  when "timestamp" then "timestamp_ntz"
  else "timestamp_tz" # timestamptz and everything epoch-like defaults safe
  end
end

# Fields of the persisted schema whose type carries a wall clock or date.
# The sync stores either the struct hash itself or a 1-element array of it.
def timestamp_columns(table)
  Array(fields_of(table)).select { |f| f["type"].to_s.match?(/\Atimestamp(tz)?\z|\bdate\b/) }
end

def fields_of(table)
  schema = table.schema_json
  schema = schema.first if schema.is_a?(Array)
  schema.is_a?(Hash) ? schema["fields"] : []
end
