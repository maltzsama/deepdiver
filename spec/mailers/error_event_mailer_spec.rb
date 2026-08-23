require "rails_helper"

RSpec.describe ErrorEventMailer, type: :mailer do
  describe "#assignment_notification" do
    let(:admin) { create(:user, :admin) }
    let(:event) do
      ErrorEvent.record(catalog: nil, schema: "reporting", table: "dwd_orders", operation: "sync-table",
                        source_system: "catalog", message: "connection timed out")
    end

    let(:mail) { described_class.assignment_notification(to: "oncall@example.com", event: event, assigned_by: admin) }

    it "addresses the assignee and points to the event" do
      expect(mail.to).to eq([ "oncall@example.com" ])
      expect(mail.subject).to include("sync-table")
      expect(mail.body.encoded).to include("connection timed out")
      expect(mail.body.encoded).to include(admin.email)
    end
  end
end
