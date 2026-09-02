# Operator-facing configuration of the ephemeral Trino engine the application
# scales up to run maintenance. A single row (singleton) drives how the
# provisioner materialises the engine on the next start: single-node
# (coordinator also runs tasks) or a coordinator + separate workers, with the
# CPU/memory of each node, and the Iceberg connector's retention floors.
class TrinoEngineConfig < ApplicationRecord
  include SingletonModel

  TOPOLOGIES = %w[single cluster].freeze

  validates :topology, inclusion: { in: TOPOLOGIES }
  validates :worker_replicas, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :coordinator_cpu, :coordinator_memory, :worker_cpu, :worker_memory, presence: true
  validates :expire_snapshots_min_retention, :remove_orphan_files_min_retention, presence: true
  validate :retention_floors_are_durations

  # The singleton config row, created with production defaults on first access.
  #
  # @return [TrinoEngineConfig] the config row
  def self.instance
    super(defaults)
  end

  # The defaults used when the row does not exist yet.
  #
  # @return [Hash] default attributes
  def self.defaults
    {
      topology: "cluster",
      worker_replicas: 2,
      coordinator_cpu: "2",
      coordinator_memory: "2Gi",
      worker_cpu: "1",
      worker_memory: "2Gi",
      expire_snapshots_min_retention: "7d",
      remove_orphan_files_min_retention: "7d"
    }
  end

  # The Iceberg connector properties these floors map to, ready to merge into
  # the catalog projection. Keyed by the Trino property name so the projection
  # does not have to know which column feeds which key.
  #
  # @return [Hash{String => String}] the connector properties
  def connector_retention_properties
    {
      "iceberg.expire-snapshots.min-retention" => expire_snapshots_min_retention,
      "iceberg.remove-orphan-files.min-retention" => remove_orphan_files_min_retention
    }.compact_blank
  end

  # The configured floor, in seconds, for a maintenance operation - or nil when
  # the operation has no floor or the value does not parse as a time duration.
  #
  # @param operation [String] the maintenance operation
  # @return [Float, nil] the floor in seconds
  def retention_floor_seconds(operation)
    value = case operation
    when "expire_snapshots"    then expire_snapshots_min_retention
    when "remove_orphan_files" then remove_orphan_files_min_retention
    end
    value.nil? ? nil : TrinoDuration.to_seconds(value)
  end

  # Whether the engine runs as a coordinator with separate workers.
  #
  # @return [Boolean]
  def cluster?
    topology == "cluster"
  end

  private

  # The floors are interpolated into connector properties, and are compared
  # against each step's retention, so they must be a magnitude plus a TIME unit
  # - "7d" is valid, "128MB" is well formed but meaningless as a retention.
  def retention_floors_are_durations
    %i[expire_snapshots_min_retention remove_orphan_files_min_retention].each do |field|
      value = self[field]
      next if value.blank?
      next if TrinoDuration.to_seconds(value)

      errors.add(field, :invalid_duration)
    end
  end
end
