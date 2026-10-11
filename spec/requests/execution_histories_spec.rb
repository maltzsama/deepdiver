require "rails_helper"

RSpec.describe "Execution histories maintenance list", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it "lists maintenance executions" do
    create(:execution_history, iceberg_table: create(:iceberg_table), status: "success",
                               started_at: 2.hours.ago)

    get execution_histories_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("maintenance")
  end

  it "filters the list to one table" do
    target = create(:iceberg_table)
    other  = create(:iceberg_table)
    create(:execution_history, iceberg_table: target, status: "success", started_at: 1.hour.ago)
    create(:execution_history, iceberg_table: other, status: "success", started_at: 1.hour.ago)

    get execution_histories_path(table_id: target.id)

    expect(response.body).to include(target.fully_qualified_name)
    expect(response.body).not_to include(other.fully_qualified_name)
  end

  it "filters the list by operation" do
    optimize = create(:iceberg_table)
    expire   = create(:iceberg_table)
    first  = create(:execution_history, iceberg_table: optimize, status: "success",
                                        started_at: 2.hours.ago)
    second = create(:execution_history, iceberg_table: expire, status: "success",
                                        started_at: 1.hour.ago)
    create(:execution_step, execution_history: first, operation: "optimize", status: "succeeded")
    create(:execution_step, execution_history: second, operation: "expire_snapshots", status: "succeeded")

    get execution_histories_path(operation: "optimize")

    expect(response.body).to include(optimize.fully_qualified_name)
    expect(response.body).not_to include(expire.fully_qualified_name)
  end

  it "does not expose the removed triage routes" do
    event = ErrorEvent.record(catalog: create(:catalog), schema: "s", table: "t",
                              operation: "catalog-sync", source_system: "catalog",
                              message: "boom")

    patch "/execution_histories/#{event.id}/acknowledge"

    expect(response).to have_http_status(:not_found)
  end
end
