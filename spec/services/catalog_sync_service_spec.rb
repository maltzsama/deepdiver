require "rails_helper"

RSpec.describe CatalogSyncService do
  class FlakyCatalogClient
    def namespaces
      [ "bronze" ]
    end

    def tables_in(_namespace)
      [ "good", "bad" ]
    end

    def table_metadata(_namespace, table)
      raise "exploded" if table == "bad"

      { "metadata" => { "current-snapshot_id" => 1, "snapshots" => [] } }
    end
  end

  it "keeps syncing when one table fails" do
    catalog = create(:catalog)

    result = CatalogSyncService.new(catalog, client: FlakyCatalogClient.new).sync

    expect(result[:errors].size).to eq(1)
    expect(result[:errors].first).to match(/bad: exploded/)
    expect(catalog.iceberg_tables.exists?(namespace: "bronze", name: "good")).to be true
    expect(catalog.iceberg_tables.exists?(namespace: "bronze", name: "bad")).to be false
  end

  class HealthStampClient
    attr_accessor :payload

    def namespaces            = [ "bronze" ]
    def tables_in(_namespace) = [ "t" ]
    def table_metadata(_namespace, _table) = payload
  end

  def health_payload(size_bytes:, data_files: 100, snapshots: 1)
    { "metadata" => {
      "table-uuid" => "uuid",
      "location" => "s3://bucket/logs",
      "current-snapshot-id" => 1,
      "snapshots" => Array.new(snapshots) do
        { "snapshot-id" => 1, "timestamp-ms" => 1_700_000_000_000,
          "summary" => { "total-records" => "1000", "total-data-files" => data_files.to_s,
                         "total-files-size-in-bytes" => size_bytes.to_s } }
      end
    } }
  end

  it "stamps health_status_changed_at only when the status CHANGES" do
    catalog = create(:catalog)
    client = HealthStampClient.new

    # Critical: tiny average file size against the 128MB target.
    client.payload = health_payload(size_bytes: 100, data_files: 100, snapshots: 60)
    CatalogSyncService.new(catalog, client: client).sync
    table = catalog.iceberg_tables.find_by!(name: "t")
    first_stamp = table.health_status_changed_at

    expect(table.health_status).to eq("critical")
    expect(first_stamp).to be_present

    # Same status again: the clock does NOT restart.
    CatalogSyncService.new(catalog, client: client, now: 2.days.from_now).sync
    expect(table.reload.health_status).to eq("critical")
    expect(table.reload.health_status_changed_at).to eq(first_stamp)

    # Status flips to healthy: a new stamp.
    client.payload = health_payload(size_bytes: 1_000_000_000_000, data_files: 10)
    CatalogSyncService.new(catalog, client: client, now: 3.days.from_now).sync
    table.reload
    expect(table.health_status).to eq("healthy")
    expect(table.health_status_changed_at).to be_within(1.second).of(3.days.from_now)
  end
end
