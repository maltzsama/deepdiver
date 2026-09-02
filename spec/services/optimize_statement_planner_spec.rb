require "rails_helper"

RSpec.describe OptimizeStatementPlanner do
  let(:plan) { create(:maintenance_plan, :with_all_steps) }
  let(:table) { plan.iceberg_table }
  let(:optimize_step) { plan.maintenance_steps.find_by!(operation: "optimize") }
  let(:runtime) { instance_double(FakeTrinoRuntime) }

  def plan_with_partition(specs)
    table.update!(partition_json: specs)
  end

  describe "when the table is not batchable" do
    it "returns the single unbatched statement for an unpartitioned table" do
      plan_with_partition([])

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
      expect(sqls.first).to include("ALTER TABLE").and include("EXECUTE optimize")
      expect(sqls.first).not_to include("WHERE")
    end

    it "returns the single statement when there are multiple partition fields" do
      plan_with_partition([ { "spec-id" => 0, "fields" => [
        { "name" => "date", "transform" => "identity" },
        { "name" => "site", "transform" => "identity" }
      ] } ])

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
    end

    it "returns the single statement when the transform is not identity" do
      plan_with_partition([ { "spec-id" => 0, "fields" => [ { "name" => "date", "transform" => "month" } ] } ])

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
    end

    it "does not batch when the operator already set a WHERE predicate" do
      plan_with_partition([ { "spec-id" => 0, "fields" => [ { "name" => "date", "transform" => "identity" } ] } ])
      optimize_step.update!(config: { "where" => "date > DATE '2026-01-01'" })
      allow(runtime).to receive(:query_rows)

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
      expect(sqls.first).to include("WHERE date > DATE '2026-01-01'")
      expect(runtime).not_to have_received(:query_rows)
    end

    it "does not batch for a non-optimize step" do
      plan_with_partition([ { "spec-id" => 0, "fields" => [ { "name" => "date", "transform" => "identity" } ] } ])
      expire_step = plan.maintenance_steps.find_by!(operation: "expire_snapshots")

      sqls = described_class.new(table, expire_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
    end
  end

  describe "when the table is batchable" do
    before do
      plan_with_partition([ { "spec-id" => 0, "fields" => [ { "name" => "ingestion_date", "transform" => "identity" } ] } ])
      allow(runtime).to receive(:query_rows).and_return(
        [ [ "2026-01-01" ], [ "2026-01-02" ], [ "2026-01-03" ] ]
      )
    end

    it "chunks partition values into bounded groups" do
      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
      expect(sqls.first).to include("WHERE \"ingestion_date\" IN (DATE '2026-01-01', DATE '2026-01-02', DATE '2026-01-03')")
      expect(runtime).to have_received(:query_rows).once
    end

    it "splits into multiple statements when there are more values than the per-query limit" do
      values = (1..200).map { |d| [ format("2026-%02d-%02d", (d - 1) / 28 + 1, (d - 1) % 28 + 1) ] }
      allow(runtime).to receive(:query_rows).and_return(values)
      optimize_step.update!(config: { "partitions_per_query" => 80 })

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(3)
      expect(sqls.each_slice(1).size).to eq(3)
    end

    it "queries the $partitions metadata table referencing the column under partition.<name>" do
      described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 42)

      expect(runtime).to have_received(:query_rows) do |sql, execution_id:|
        expect(sql).to include('"partition"."ingestion_date"')
        expect(sql).to match(/\$partitions/)
        expect(execution_id).to eq(42)
      end
    end

    it "falls back to the single statement when partition discovery returns no rows" do
      allow(runtime).to receive(:query_rows).and_return([])

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
      expect(sqls.first).not_to include("WHERE")
    end

    it "falls back to the single statement when discovery raises, surfacing an ErrorEvent" do
      allow(runtime).to receive(:query_rows).and_raise("boom")

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
      expect(sqls.first).not_to include("WHERE")
      expect(ErrorEvent.last.operation).to eq("optimize-partition-discovery")
      expect(ErrorEvent.last.message).to include("boom")
      expect(ErrorEvent.last.table).to eq(table.name)
    end

    it "uses the configured partitions-per-query when present" do
      optimize_step.update!(config: { "partitions_per_query" => 2 })

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(2)
      expect(sqls.first).to include("DATE '2026-01-01'").and include("DATE '2026-01-02'")
    end

    it "falls back to the single statement when a partition value cannot be rendered as a literal" do
      allow(runtime).to receive(:query_rows).and_return([ [ "BR" ], [ "US" ] ])
      plan_with_partition([ { "spec-id" => 0, "fields" => [ { "name" => "country", "transform" => "identity" } ] } ])

      sqls = described_class.new(table, optimize_step, runtime: runtime).statements(execution_id: 1)

      expect(sqls.size).to eq(1)
      expect(sqls.first).not_to include("WHERE")
      expect(ErrorEvent.last.operation).to eq("optimize-partition-discovery")
      expect(ErrorEvent.last.message).to include("unsupported partition value")
    end
  end

  describe "#sql_literal" do
    subject(:literal) { described_class.new(table, optimize_step, runtime: runtime) }

    it "renders a date-only value as a DATE literal" do
      expect(literal.send(:sql_literal, "2026-08-28")).to eq("DATE '2026-08-28'")
    end

    it "renders a timestamp value as a TIMESTAMP literal" do
      expect(literal.send(:sql_literal, "2026-08-28T12:57:08")).to eq("TIMESTAMP '2026-08-28 12:57:08'")
    end

    it "renders a space-separated timestamp with fractional seconds" do
      expect(literal.send(:sql_literal, "2026-08-28 12:57:08.000")).to eq("TIMESTAMP '2026-08-28 12:57:08.000'")
    end

    it "rejects a timestamp with trailing content (anchored regex)" do
      expect { literal.send(:sql_literal, "2026-08-28T12:57 OR 1=1") }
        .to raise_error(ArgumentError, /unsupported partition value/)
    end
  end
end
