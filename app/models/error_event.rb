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
