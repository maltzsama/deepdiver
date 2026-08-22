require "rails_helper"

RSpec.describe TrinoClient, "pagination" do
  let(:transport) { instance_double(HttpTransport) }
  let(:client) { TrinoClient.new(endpoint: "http://trino:8080", transport: transport) }

  let(:columns) { [ { "name" => "max_ts" } ] }
  let(:row)     { [ "2026-08-19 14:07:34.368 UTC" ] }

  describe "run_with_names" do
    it "keeps rows delivered on pages before the final one" do
      page1 = { "columns" => columns, "data" => [ row ], "nextUri" => "http://trino:8080/v1/statement/1/2" }
      page2 = { "columns" => columns, "data" => nil }

      allow(transport).to receive(:post)
        .with("http://trino:8080/v1/statement", body: "SQL", headers: anything)
        .and_return(page1)
      allow(transport).to receive(:get)
        .with("http://trino:8080/v1/statement/1/2", headers: anything)
        .and_return(page2)

      expect(client.run_with_names("SQL")).to eq([ { "max_ts" => "2026-08-19 14:07:34.368 UTC" } ])
    end

    it "returns single-page results untouched" do
      page = { "columns" => columns, "data" => [ row ] }
      allow(transport).to receive(:post)
        .with("http://trino:8080/v1/statement", body: "SQL", headers: anything)
        .and_return(page)

      expect(client.run_with_names("SQL")).to eq([ { "max_ts" => row[0] } ])
    end

    it "raises when the query fails mid-pagination" do
      page1 = { "columns" => columns, "data" => [], "nextUri" => "http://trino:8080/v1/statement/1/2" }
      page2 = { "error" => { "message" => "boom" } }

      allow(transport).to receive(:post).and_return(page1)
      allow(transport).to receive(:get).and_return(page2)

      expect { client.run_with_names("SQL") }.to raise_error(TrinoClient::Error, /boom/)
    end
  end

  describe "query_scalar" do
    it "stops paginating after the first row" do
      page1 = { "columns" => columns, "data" => [ row ], "nextUri" => "http://trino:8080/v1/statement/1/2" }

      allow(transport).to receive(:post)
        .with("http://trino:8080/v1/statement", body: "SQL", headers: anything)
        .and_return(page1)
      expect(transport).not_to receive(:get)

      expect(client.query_scalar("SQL", "max_ts")).to eq("2026-08-19 14:07:34.368 UTC")
    end

    it "returns nil when the result is empty" do
      page = { "columns" => columns, "data" => nil }
      allow(transport).to receive(:post).and_return(page)

      expect(client.query_scalar("SQL", "max_ts")).to be_nil
    end
  end

  describe "query_timeout" do
    it "raises when a query exceeds the per-query timeout" do
      timed_out_client = TrinoClient.new(endpoint: "http://trino:8080", transport: transport, query_timeout: 0.1)
      page = { "columns" => columns, "data" => [ row ], "nextUri" => "http://trino:8080/v1/statement/1/2" }

      allow(transport).to receive(:post).and_return(page)
      # Keep returning pages with nextUri so the loop never exits normally;
      # the deadline check triggers instead.
      allow(transport).to receive(:get).and_return(
        { "columns" => columns, "data" => [], "nextUri" => "http://trino:8080/v1/statement/1/3" }
      )

      expect { timed_out_client.run_with_names("SQL") }.to raise_error(TrinoClient::Error, /exceeded/)
    end
  end

  describe "query_column" do
    it "returns column values across all rows" do
      cols = [ { "name" => "p" } ]
      page = { "columns" => cols, "data" => [ [ "a" ], [ "b" ] ] }
      allow(transport).to receive(:post).and_return(page)

      expect(client.query_column("SQL", "p")).to eq(%w[a b])
    end
  end
end
