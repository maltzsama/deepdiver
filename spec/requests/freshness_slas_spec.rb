require "rails_helper"

RSpec.describe "FreshnessSlas", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user, role: "viewer") }
  let(:table)  { create(:iceberg_table) }

  describe "authorization" do
    it "lets an admin edit the SLA" do
      sign_in admin
      get edit_iceberg_table_freshness_sla_path(table)

      expect(response).to have_http_status(:ok)
    end

    it "does not let a viewer edit the SLA" do
      sign_in viewer
      get edit_iceberg_table_freshness_sla_path(table)
      follow_redirect!

      expect(response.body).to include("You do not have permission")
    end
  end

  describe "PATCH /iceberg_tables/:id/freshness_sla" do
    before { sign_in admin }

    it "creates the SLA with custom severity bands and alert destination" do
      patch iceberg_table_freshness_sla_path(table),
            params: { table_freshness_sla: {
              enabled: "1",
              timestamp_column: "load_ts",
              timestamp_type: "timestamp_tz",
              source_timezone: "UTC",
              partition_lookback: "7",
              sla_minutes: "60",
              warning_at_percent: "80",
              warning_after_minutes: "60",
              severe_after_minutes: "120",
              critical_after_minutes: "240",
              slack_channel: "#support",
              email_to: "support@example.com"
            } }

      sla = table.reload.table_freshness_sla
      expect(sla).to be_present
      expect(sla).to have_attributes(
        enabled: true,
        sla_minutes: 60,
        warning_after_minutes: 60,
        severe_after_minutes: 120,
        critical_after_minutes: 240,
        slack_channel: "#support",
        email_to: "support@example.com"
      )
      expect(response).to redirect_to(table)
    end

    it "updates an existing SLA" do
      existing = create(:table_freshness_sla, iceberg_table: table, critical_after_minutes: 720)

      patch iceberg_table_freshness_sla_path(table),
            params: { table_freshness_sla: { critical_after_minutes: "600" } }

      expect(existing.reload.critical_after_minutes).to eq(600)
    end

    it "rejects unordered bands" do
      patch iceberg_table_freshness_sla_path(table),
            params: { table_freshness_sla: { timestamp_column: "load_ts", severe_after_minutes: "30", critical_after_minutes: "20" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
