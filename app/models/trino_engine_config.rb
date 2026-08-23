# Operator-facing configuration of the ephemeral Trino engine the application
# scales up to run maintenance. A single row (singleton) drives how the
# provisioner materialises the engine on the next start: single-node
# (coordinator also runs tasks) or a coordinator + separate workers, with the
# CPU/memory of each node.
class TrinoEngineConfig < ApplicationRecord
  TOPOLOGIES = %w[single cluster].freeze

  validates :topology, inclusion: { in: TOPOLOGIES }
  validates :worker_replicas, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :coordinator_cpu, :coordinator_memory, :worker_cpu, :worker_memory, presence: true

  # The singleton config row, created with production defaults on first access.
  #
  # @return [TrinoEngineConfig] the config row
  def self.instance
    first_or_create!(defaults)
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
      worker_memory: "2Gi"
    }
  end

  # Whether the engine runs as a coordinator with separate workers.
  #
  # @return [Boolean]
  def cluster?
    topology == "cluster"
  end
end
