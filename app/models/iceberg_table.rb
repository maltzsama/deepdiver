# A table in a catalog discovered or registered by the application. Tracks the
# table's health, freshness history, maintenance schedules, and executions.
class IcebergTable < ApplicationRecord
  HEALTH_STATUSES = %w[unknown healthy warning critical].freeze

  belongs_to :catalog, counter_cache: true

  has_one :maintenance_plan, dependent: :destroy
  has_one :table_freshness_sla, dependent: :destroy
  has_one :latest_freshness_check, -> { order(checked_at: :desc) }, class_name: "FreshnessCheck"
  has_many :freshness_checks, dependent: :destroy
  has_many :execution_histories, dependent: :destroy

  enum :health_status, HEALTH_STATUSES.to_h { |s| [ s, s ] }

  validates :namespace, :name, presence: true
  validates :name, uniqueness: { scope: %i[catalog_id namespace],
                                 conditions: -> { where(active: true) } }
  validates :table_uuid, uniqueness: { scope: :catalog_id }, if: :table_uuid
  validates :health_score, numericality: { only_integer: true, in: 0..100 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  # Marks the table as inactive after being dropped from its catalog, keeping
  # its history and configuration recorded.
  def deactivate!(at: Time.current)
    update!(active: false, deactivated_at: at)
  end

  # Namespace and table name joined with a dot.
  # @return [String]
  def fully_qualified_name
    "#{namespace}.#{name}"
  end

  # Average size of the table's data files, or nil when the stats are unknown.
  # @return [Integer, nil]
  def average_file_size
    return nil if total_size_bytes.nil? || total_data_files.nil? || total_data_files.zero?

    total_size_bytes / total_data_files
  end

  # Snapshot of key metadata fields for before/after comparison.
  # Only includes fields that maintenance operations actually move.
  # @return [Hash] the metadata snapshot
  def metadata_snapshot
    {
      "total_records"    => total_records,
      "total_data_files" => total_data_files,
      "total_size_bytes" => total_size_bytes,
      "position_deletes" => position_deletes,
      "equality_deletes" => equality_deletes,
      "snapshot_count"   => snapshot_count,
      "manifest_count"   => manifest_count,
      "oldest_snapshot_at" => oldest_snapshot_at&.iso8601
    }
  end

  # Trino SQL identifier, always exactly three parts: catalog.schema.table.
  # The whole namespace stays inside a single quoted part; the Iceberg
  # connector rebuilds the nested Namespace from its separator. Never split
  # a dotted namespace into multiple identifier parts.
  #   "catalog"."ns1.ns2.ns3"."table"
  def trino_identifier
    [ catalog.trino_catalog_name, namespace, name ].map { |part| quote_identifier(part) }.join(".")
  end

  # Trino SQL identifier for an Iceberg metadata table ($files, $manifests,
  # $snapshots, $partitions). The suffix is part of the table name and must
  # be inside the quotes:
  #   "catalog"."ns"."table$files"
  #
  # @param suffix [String] the metadata table suffix (e.g. "files", "manifests")
  # @return [String] the quoted three-part identifier
  def trino_metadata_table(suffix)
    [ catalog.trino_catalog_name, namespace, "#{name}$#{suffix}" ]
      .map { |part| quote_identifier(part) }.join(".")
  end

  private

  # Quotes an identifier for use inside a Trino SQL statement, escaping any
  # embedded double quotes.
  # @param part [String] the identifier part to quote
  # @return [String] the quoted identifier
  def quote_identifier(part)
    %("#{part.to_s.gsub('"', '""')}")
  end
end
