require "rails_helper"
require "rake"

RSpec.describe "demo:freshness_sla" do
  let(:table) do
    create(:iceberg_table, namespace: "bronze.vendas", name: "pedidos",
                           last_data_update: 6.hours.ago,
                           schema_json: { "type" => "struct", "fields" => [
                             { "id" => 1, "name" => "id", "type" => "long" },
                             { "id" => 2, "name" => "load_timestamp", "type" => "timestamptz" }
                           ] })
  end

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("demo:freshness_sla")
    Rake::Task["demo:freshness_sla"].reenable
    Rake.application.last_description = nil
    allow(MaintenanceOrchestrator).to receive(:enqueue_freshness_sweep)
  end

  it "creates one tight SLA on the stalest table, deriving the timestamp column" do
    table
    expect { Rake.application.invoke_task("demo:freshness_sla") }
      .to change(TableFreshnessSla, :count).by(1)

    sla = TableFreshnessSla.last
    expect(sla.iceberg_table).to eq(table)
    expect(sla.sla_minutes).to eq(5)
    expect(sla.timestamp_column).to eq("load_timestamp")
    expect(sla.timestamp_type).to eq("timestamp_tz")
    expect(MaintenanceOrchestrator).to have_received(:enqueue_freshness_sweep)
  end

  it "never rewrites an existing SLA" do
    table
    create(:table_freshness_sla, iceberg_table: table, sla_minutes: 999,
                                 timestamp_column: "load_timestamp",
                                 timestamp_type: "timestamp_tz")

    expect { Rake.application.invoke_task("demo:freshness_sla") }
      .not_to change { table.reload.table_freshness_sla.sla_minutes }
  end

  it "handles the array-wrapped schema shape the sync stores" do
    table
    table.update!(schema_json: [ table.schema_json ])

    expect { Rake.application.invoke_task("demo:freshness_sla") }
      .to change(TableFreshnessSla, :count).by(1)
  end

  it "aborts with guidance when the schema has no timestamp column" do
    create(:iceberg_table, last_data_update: 9.hours.ago,
                           schema_json: { "fields" => [ { "name" => "id", "type" => "long" } ] })

    expect { Rake.application.invoke_task("demo:freshness_sla") }
      .to raise_error(SystemExit, /configure its SLA manually/)
  end
end
