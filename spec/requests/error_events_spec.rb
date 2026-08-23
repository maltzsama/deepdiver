require "rails_helper"

RSpec.describe "ErrorEvents", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

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

    it "keeps the status filters visible when a filter has no results" do
      get error_events_path(status: "acknowledged")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acknowledged")
      expect(response.body).not_to include("data-table")
    end

    it "renders an empty state without events" do
      get error_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No error events")
    end
  end

  describe "GET /error_events/:id" do
    before { sign_in user }

    it "shows the full detail" do
      event = ErrorEvent.record(catalog: nil, schema: "reporting", table: "t", operation: "sync-table",
                                source_system: "catalog", message: "boom", context: { attempt: 2 })

      get error_event_path(event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("boom")
      expect(response.body).to include("attempt")
    end
  end

  describe "PATCH /error_events/:id/assign" do
    before { sign_in admin }

    it "assigns to a user, keeps the event open and sends the email" do
      operator = create(:user, :operator)
      event = ErrorEvent.record(catalog: nil, schema: "s", operation: "sync-table", source_system: "catalog", message: "m")

      expect {
        patch assign_error_event_path(event), params: { target_type: "user", target_id: operator.id }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(event.reload.status).to eq("open")
      expect(event.assigned_to).to eq(operator)
      expect(ActionMailer::Base.deliveries.last.to).to include(operator.email)
      expect(response).to redirect_to(error_event_path(event))
    end

    it "emails every team responder when assigning to a team" do
      team = create(:team)
      team.members << create(:user, :admin) << create(:user, :operator)
      event = ErrorEvent.record(catalog: nil, schema: "s", operation: "sync-table", source_system: "catalog", message: "m")

      expect {
        patch assign_error_event_path(event), params: { target_type: "team", target_id: team.id }
      }.to change { ActionMailer::Base.deliveries.count }.by(2)

      expect(event.reload.assigned_to).to be_nil
      expect(event.context["assigned_team"]).to eq(team.name)
    end

    it "rejects viewers as assignment targets" do
      viewer = create(:user)
      event = ErrorEvent.record(catalog: nil, schema: "s", operation: "sync-table", source_system: "catalog", message: "m")

      patch assign_error_event_path(event), params: { target_type: "user", target_id: viewer.id }

      expect(flash[:alert]).to be_present
      expect(event.reload.assigned_to).to be_nil
    end

    it "forbids viewers from assigning" do
      event = ErrorEvent.record(catalog: nil, schema: "s", operation: "sync-table", source_system: "catalog", message: "m")
      sign_in user

      patch assign_error_event_path(event), params: { target_type: "user", target_id: admin.id }

      expect(response).to redirect_to(root_path)
      expect(event.reload.assigned_to).to be_nil
    end
  end

  describe "PATCH /error_events/:id/acknowledge" do
    before { sign_in admin }

    it "lets the admin acknowledge an open event" do
      event = ErrorEvent.record(catalog: nil, schema: "s", operation: "sync-table", source_system: "catalog", message: "m")

      patch acknowledge_error_event_path(event)

      expect(event.reload.status).to eq("acknowledged")
      expect(response).to redirect_to(error_event_path(event))
    end
  end

  describe "PATCH /error_events/:id/resolve" do
    before { sign_in admin }

    it "resolves an acknowledged event" do
      event = ErrorEvent.record(catalog: nil, schema: "s", operation: "sync-table", source_system: "catalog", message: "m")
      event.acknowledge!(user: admin)

      patch resolve_error_event_path(event)

      expect(event.reload).to be_resolved
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
