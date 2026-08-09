require "rails_helper"

RSpec.describe MaintenancePolicy do
  let(:catalog) { create(:catalog) }
  let(:tables) { create_list(:iceberg_table, 3, catalog:) }

  let(:policy) do
    described_class.create!(
      name: "Streaming optimize", cron: "0 */6 * * *",
      steps_config: { "optimize" => { "enabled" => "1", "file_size_threshold" => "256MB" } }
    )
  end

  describe "validations" do
    it "rejects an invalid cron" do
      p = described_class.new(name: "x", cron: "0 99 99 99 99")

      expect(p).not_to be_valid
      expect(p.errors[:cron]).to be_present
    end
  end

  describe "#apply_to!" do
    it "creates one plan per table with the configured steps" do
      result = policy.apply_to!(tables)

      expect(result).to eq(created: 3, updated: 0, skipped: 0)
      expect(policy.maintenance_plans.count).to eq(3)
      plan = policy.maintenance_plans.first
      expect(plan.cron).to eq("0 */6 * * *")
      expect(plan.maintenance_steps.find_by(operation: "optimize").config)
        .to eq("file_size_threshold" => "256MB")
    end

    it "adopts an existing plan that has no policy yet" do
      orphan = create(:maintenance_plan, iceberg_table: tables.first, cron: "0 1 * * *")

      result = policy.apply_to!([ tables.first ])

      expect(result).to eq(created: 0, updated: 1, skipped: 0)
      expect(orphan.reload.maintenance_policy).to eq(policy)
      expect(orphan.cron).to eq("0 */6 * * *")
    end

    it "is idempotent: reapplying does not duplicate" do
      policy.apply_to!(tables)
      result = policy.apply_to!(tables)

      expect(result).to eq(created: 0, updated: 3, skipped: 0)
      expect(policy.maintenance_plans.count).to eq(3)
    end

    it "does NOT steal a plan from another policy" do
      other = described_class.create!(name: "Batch", cron: "0 3 * * *")
      other.apply_to!([ tables.first ])

      result = policy.apply_to!([ tables.first ])

      expect(result).to eq(created: 0, updated: 0, skipped: 1)
      expect(tables.first.maintenance_plan.maintenance_policy).to eq(other)
    end
  end

  describe "#propagate!" do
    before { policy.apply_to!(tables) }

    it "syncs cron and step config to every plan" do
      policy.update!(cron: "0 */4 * * *",
                     steps_config: { "optimize" => { "enabled" => "1", "file_size_threshold" => "512MB" } })
      count = policy.propagate!

      expect(count).to eq(3)
      expect(policy.maintenance_plans.pluck(:cron).uniq).to eq([ "0 */4 * * *" ])
      expect(policy.maintenance_plans.first.maintenance_steps.find_by(operation: "optimize").config)
        .to eq("file_size_threshold" => "512MB")
    end

    it "PRESERVES a pause from repeated failures" do
      paused = policy.maintenance_plans.first
      paused.update!(is_paused: true, consecutive_failures: 3)

      policy.update!(cron: "0 */4 * * *")
      policy.propagate!

      expect(paused.reload).to be_paused
      expect(paused.consecutive_failures).to eq(3)
      expect(paused.cron).to eq("0 */4 * * *")
    end
  end

  describe "destruction" do
    it "does not delete the plans, only unlinks them" do
      policy.apply_to!(tables)

      expect { policy.destroy }.not_to change(MaintenancePlan, :count)
      expect(MaintenancePlan.pluck(:maintenance_policy_id).uniq).to eq([ nil ])
    end
  end
end
