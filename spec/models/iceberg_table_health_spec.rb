require "rails_helper"

RSpec.describe IcebergTable, "health persistence" do
  let(:table) { create(:iceberg_table) }
  let(:evaluation) do
    { score: 42, status: :warning, coverage: 90,
      components: { fragmentation: 0.3, snapshot_buildup: 0.8,
                    delete_overhead: 1.0, manifest_buildup: nil },
      worst_component: :fragmentation, worst_ratio: 0.3,
      details: { average_file_size: 1024, snapshot_count: 12, snapshot_budget: 10 } }
  end

  describe "#health_attributes" do
    it "writes the score, the label and the breakdown together" do
      at = Time.zone.parse("2026-09-02 10:00")
      attributes = table.health_attributes(evaluation, at: at)

      expect(attributes[:health_score]).to eq(42)
      expect(attributes[:health_status]).to eq("warning")
      expect(attributes[:health_evaluated_at]).to eq(at)
      expect(attributes[:health_components]["components"]).to include("fragmentation" => 0.3)
    end

    it "stamps health_status_changed_at only when the label changes" do
      table.update!(health_status: "warning")

      expect(table.health_attributes(evaluation)).not_to have_key(:health_status_changed_at)
      expect(table.health_attributes(evaluation.merge(status: :critical)))
        .to have_key(:health_status_changed_at)
    end

    it "returns nothing when the evaluation produced no score" do
      expect(table.health_attributes(evaluation.merge(score: nil))).to eq({})
    end
  end

  describe "#persisted_health_evaluation" do
    it "round-trips into the shape the evaluator returns" do
      table.update!(table.health_attributes(evaluation))

      read = table.reload.persisted_health_evaluation

      expect(read[:score]).to eq(42)
      expect(read[:status]).to eq(:warning)
      expect(read[:coverage]).to eq(90)
      expect(read[:worst_component]).to eq(:fragmentation)
      expect(read[:components][:fragmentation]).to eq(0.3)
      expect(read[:details][:snapshot_budget]).to eq(10)
    end

    it "is nil until a breakdown has been persisted" do
      expect(table.persisted_health_evaluation).to be_nil
    end
  end

  it "makes the list and the detail read the same evaluation" do
    table.update!(table.health_attributes(evaluation))
    table.reload

    # The list renders the columns; the detail renders the persisted evaluation.
    detail = table.persisted_health_evaluation

    expect(detail[:score]).to eq(table.health_score)
    expect(detail[:status].to_s).to eq(table.health_status)
  end
end
