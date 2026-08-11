# Aggregated record of a failure observed across the system. Uses rising-edge
# capture so multiple call sites raising the same error produce a single event
# whose occurrence_count grows over time.
class ErrorEvent < ApplicationRecord
  SEVERITIES = %w[error warning info].freeze
  STATUSES = %w[open acknowledged resolved].freeze
  SYSTEMS = %w[catalog-sync execution sso engine].freeze

  belongs_to :catalog, optional: true

  validates :schema, :operation, :source_system, presence: true
  validates :severity, inclusion: { in: SEVERITIES }
  validates :status, inclusion: { in: STATUSES }

  scope :open, -> { where(status: "open") }
  scope :acknowledged, -> { where(status: "acknowledged") }
  scope :resolved, -> { where(status: "resolved") }
  scope :catalog_events, ->(catalog) { where(catalog_id: catalog.id) }
  scope :table_events, ->(table) do
    where(schema: table.namespace, table: table.name)
  end

  # Rising-edge capture: whoever RAISES records first, whoever RESCUES does not
  # overwrite. Guarantees one event per failure moment, not one per call site.
  class << self
    # Records an error occurrence, incrementing a matching existing event or
    # creating a new one. The first writer wins; later rescues do not overwrite.
    # @param catalog [Catalog, nil] the catalog the failure relates to, if any
    # @param schema [String] the namespace where the failure occurred
    # @param table [String, nil] the table where the failure occurred
    # @param operation [String] the operation that was being performed
    # @param source_system [String] the subsystem that reported the failure
    # @param error_class [String] the Ruby error class name
    # @param message [String] the error message
    # @param severity [String] one of the SEVERITIES
    # @param context [Hash] extra structured context stored on the event
    # @param source_column [String, nil] the column the failure relates to, if any
    # @return [ErrorEvent] the created or updated event
    def record(catalog:, schema:, table: nil, operation:, source_system:,
               error_class: "StandardError", message:, severity: "error",
               context: {}, source_column: nil)
      event = find_or_initialize_by(
        catalog_id: catalog&.id,
        schema: schema,
        table: table.to_s,
        operation: operation,
        source_system: source_system,
        message: message
      )

      if event.persisted?
        event.update!(
          last_seen_at: Time.current,
          occurrence_count: event.occurrence_count + 1,
          context: event.context.merge(context.compact.transform_keys(&:to_s))
        )
      else
        event.assign_attributes(
          error_class: error_class,
          severity: severity,
          status: "open",
          context: context.compact.transform_keys(&:to_s),
          source_column: source_column,
          first_seen_at: Time.current,
          last_seen_at: Time.current,
          occurrence_count: 1
        )
        event.save!
      end

      event
    end
  end
end
