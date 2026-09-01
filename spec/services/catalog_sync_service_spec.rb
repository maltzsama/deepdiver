require "rails_helper"

RSpec.describe CatalogSyncService do
  before do
    materializer = instance_double(TrinoSecretMaterializer)
    allow(TrinoSecretMaterializer).to receive(:new).and_return(materializer)
    allow(materializer).to receive(:materialize!)
  end
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

  def health_payload(size_bytes:, data_files: 100, snapshots: 1, oldest_ms: 1_700_000_000_000)
    { "metadata" => {
      "table-uuid" => "uuid",
      "location" => "s3://bucket/logs",
      "current-snapshot-id" => snapshots,
      "snapshots" => Array.new(snapshots) do |i|
        { "snapshot-id" => i + 1, "timestamp-ms" => oldest_ms + (i * 86_400_000),
          "summary" => { "total-records" => "1000", "total-data-files" => data_files.to_s,
                         "total-files-size-in-bytes" => size_bytes.to_s } }
      end
    } }
  end

  it "stamps health_status_changed_at only when the status CHANGES" do
    catalog = create(:catalog)
    client = HealthStampClient.new

    # Critical: tiny average file size against the 128MB target. Snapshots span
    # 60 days (1/day), so the rate-based snapshot budget is 7 → snapshot_buildup
    # is 0 and the tiny files push the table to critical.
    client.payload = health_payload(size_bytes: 100, data_files: 100, snapshots: 60,
                                    oldest_ms: 60.days.ago.to_i * 1000)
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

  class DropAwareClient
    attr_accessor :present, :uuid

    def namespaces            = [ "bronze" ]
    def tables_in(_namespace) = present ? [ "t" ] : []

    def table_metadata(_namespace, _table)
      { "metadata" => { "table-uuid" => uuid, "location" => "s3://bucket/logs",
                        "current-snapshot-id" => 1, "snapshots" => [] } }
    end
  end

  it "soft-deletes tables that disappeared from the catalog" do
    catalog = create(:catalog)
    client = DropAwareClient.new
    client.uuid = "uuid-1"
    client.present = true
    CatalogSyncService.new(catalog, client: client).sync

    table = catalog.iceberg_tables.find_by!(name: "t")
    expect(table).to be_active

    client.present = false
    CatalogSyncService.new(catalog, client: client).sync

    expect(table.reload).not_to be_active
    expect(table.deactivated_at).to be_present
    expect(catalog.iceberg_tables).to include(table)
  end

  it "recreates a table as a NEW row when it reappears with a new uuid" do
    catalog = create(:catalog)
    client = DropAwareClient.new
    client.uuid = "uuid-1"
    client.present = true
    CatalogSyncService.new(catalog, client: client).sync
    old = catalog.iceberg_tables.find_by!(name: "t")
    expect(old).to be_active

    # Table dropped...
    client.present = false
    CatalogSyncService.new(catalog, client: client).sync
    expect(old.reload).not_to be_active

    # ...then recreated with a NEW uuid: the old row stays recorded and a new
    # active row appears alongside it.
    client.uuid = "uuid-2"
    client.present = true
    CatalogSyncService.new(catalog, client: client).sync

    expect(old.reload).not_to be_active
    new_table = catalog.iceberg_tables.active.find_by(name: "t")
    expect(new_table).to be_present
    expect(new_table.id).not_to eq(old.id)
  end

  describe "deactivation safety" do
    # A table absent from `seen` because its sync errored has NOT been dropped
    # from the catalog. Deactivating it removes it from the tables screen, from
    # freshness sweeps (which filter on active) and from maintenance dispatch.
    class NamespaceListingFails
      def namespaces            = [ "bronze" ]
      def tables_in(_namespace) = raise "catalog unreachable"
      def table_metadata(_n, _t) = {}
    end

    class TableSyncFails
      def namespaces            = [ "bronze" ]
      def tables_in(_namespace) = [ "t" ]
      def table_metadata(_n, _t) = raise "metadata unreadable"
    end

    class EmptyNamespace
      def namespaces            = [ "bronze" ]
      def tables_in(_namespace) = []
      def table_metadata(_n, _t) = {}
    end

    it "does not deactivate the catalog when every namespace fails to list" do
      catalog = create(:catalog)
      a = create(:iceberg_table, catalog: catalog, namespace: "bronze", name: "a", active: true)
      b = create(:iceberg_table, catalog: catalog, namespace: "bronze", name: "b", active: true)

      described_class.new(catalog, client: NamespaceListingFails.new).sync

      # `where.not(id: [])` renders as `1=1`, so an empty `seen` used to take
      # out every active table in the catalog.
      expect(a.reload.active).to be(true)
      expect(b.reload.active).to be(true)
    end

    it "does not deactivate a table whose own sync failed" do
      catalog = create(:catalog)
      table = create(:iceberg_table, catalog: catalog, namespace: "bronze", name: "t", active: true)

      result = described_class.new(catalog, client: TableSyncFails.new).sync

      expect(result[:errors].size).to eq(1)
      expect(table.reload.active).to be(true)
    end

    it "still deactivates a table the catalog no longer lists" do
      catalog = create(:catalog)
      dropped = create(:iceberg_table, catalog: catalog, namespace: "bronze", name: "gone", active: true)

      described_class.new(catalog, client: EmptyNamespace.new).sync

      expect(dropped.reload.active).to be(false)
    end

    it "leaves tables of an unlisted namespace alone" do
      catalog = create(:catalog)
      other = create(:iceberg_table, catalog: catalog, namespace: "silver", name: "x", active: true)

      described_class.new(catalog, client: EmptyNamespace.new).sync

      expect(other.reload.active).to be(true)
    end
  end
end
