require "rails_helper"

RSpec.describe "ErrorEvents", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

  describe "recording" do
    it "records a failure with rising-edge capture (does not duplicate)" do
      catalog = create(:catalog)

      expect do
        2.times do
          ErrorEvent.record(catalog: catalog, schema: "reporting", table: "dwd_orders",
                            operation: "sync-table", source_system: "catalog",
                            error_class: "Timeout::Error", message: "connection timed out")
        end
      end.to change(ErrorEvent, :count).by(1)

      event = ErrorEvent.last
      expect(event.occurrence_count).to eq(2)
      expect(event.table).to eq("dwd_orders")
    end

    it "records a distinct failure as a new event" do
      catalog = create(:catalog)

      ErrorEvent.record(catalog: catalog, schema: "reporting", operation: "sync-namespace",
                        source_system: "catalog", error_class: "RuntimeError", message: "boom")
      ErrorEvent.record(catalog: catalog, schema: "reporting", operation: "sync-namespace",
                        source_system: "catalog", error_class: "RuntimeError", message: "other")

      expect(ErrorEvent.count).to eq(2)
    end
  end

  describe "GET /error_events" do
    before { sign_in user }

    it "lists events" do
      catalog = create(:catalog)
      ErrorEvent.record(catalog: catalog, schema: "reporting", operation: "sync-table",
                        source_system: "catalog", message: "boom")

      get error_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("boom")
    end

    it "renders an empty state without events" do
      get error_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No error events")
    end
  end

  describe "overview banner" do
    it "shows open errors on the dashboard" do
      sign_in user
      catalog = create(:catalog)
      ErrorEvent.record(catalog: catalog, schema: "reporting", operation: "sync-table",
                        source_system: "catalog", message: "boom")

      get root_path

      expect(response.body).to include("1 open error")
    end
  end
end
