# Aggregated record of a failure observed across the system. Uses rising-edge
# capture so multiple call sites raising the same error produce a single event
# whose occurrence_count grows over time.
class ErrorEvent < ApplicationRecord
  SEVERITIES = %w[error warning info].freeze
  STATUSES = %w[open acknowledged resolved].freeze
  SYSTEMS = %w[catalog engine execution freshness app sso].freeze
  FRESHNESS_OPERATION = "freshness-check"

  belongs_to :catalog, optional: true
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :assigned_by, class_name: "User", optional: true

  validates :schema, :operation, :source_system, presence: true
  validates :severity, inclusion: { in: SEVERITIES }
  validates :status, inclusion: { in: STATUSES }
  validates :source_system, inclusion: { in: SYSTEMS }

  scope :open, -> { where(status: "open") }
  scope :catalog_events, ->(catalog) { where(catalog_id: catalog.id) }
  scope :table_events, ->(table) do
    # Table names are unique per catalog, not globally (see #210). Scoping on
    # schema+table alone would show every same-named table's errors from every
    # other catalog on this table's page.
    where(catalog_id: table.catalog_id, schema: table.namespace, table: table.name)
  end

  # Assigns the event to a user or to every admin/operator member of a team.
  # Assignment does NOT change the status: the event stays open until the
  # assignee acknowledges it. Returns the list of notified users.
  # @param target [User, Team] the user or team receiving the assignment
  # @param by [User] the admin/operator performing the assignment
  # @return [Array<User>] the users notified
  def assign_to!(target, by:)
    assignees = target.is_a?(Team) ? target.responders.to_a : [ target ]
    raise ArgumentError, "nothing to assign" if assignees.empty?

    update!(assigned_by: by, assigned_to: target.is_a?(User) ? target : nil,
            context: context.merge("assigned_team" => target.is_a?(Team) ? target.name : nil).compact)
    assignees
  end

  # The assignee acknowledges ownership of the problem.
  # @param user [User] who acknowledged (must be the assignee or an admin)
  def acknowledge!(user:)
    update!(status: "acknowledged", acknowledged_at: Time.current, assigned_to: assigned_to || user)
  end

  # Closes the event as fixed.
  def resolve!
    update!(status: "resolved", resolved_at: Time.current)
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
               context: {}, source_column: nil, status: "open")
      event = find_or_initialize_by(
        catalog_id: catalog&.id,
        schema: schema,
        table: table.to_s,
        operation: operation,
        source_system: source_system,
        message: message
      )

      if event.persisted?
        # A failure that recurs after a resolution invalidates it: reopen the
        # event so it does not sit silently "resolved" while still broken.
        event.last_seen_at = Time.current
        event.occurrence_count += 1
        event.context = event.context.merge(context.compact.transform_keys(&:to_s))
        if event.resolved?
          event.status = "open"
          event.resolved_at = nil
          event.acknowledged_at = nil
        end
        event.save!
      else
        event.assign_attributes(
          error_class: error_class,
          severity: severity,
          status: status,
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

    # Records (or re-opens) the single freshness event for a table. The message
    # is stable per table so rising-edge capture keeps ONE event across the
    # whole late episode instead of one per sweep.
    # @param table [IcebergTable] the late table
    # @param context [Hash] structured detail (delay, severity, sla minutes)
    # @return [ErrorEvent] the recorded event
    def record_freshness_late!(table:, context: {})
      record(
        catalog: table.catalog,
        schema: table.namespace,
        table: table.name,
        operation: FRESHNESS_OPERATION,
        source_system: "freshness",
        error_class: "FreshnessSlaBreached",
        message: "Freshness SLA breached",
        severity: context[:severity] == "critical" ? "error" : "warning",
        context: context
      )
    end

    # Auto-resolves the open/acknowledged freshness events of a table when a
    # probe reports the data inside SLA again.
    # @param table [IcebergTable] the recovered table
    # @return [Integer] how many events were resolved
    def resolve_freshness!(table:)
      where(operation: FRESHNESS_OPERATION, status: %w[open acknowledged],
            schema: table.namespace, table: table.name, catalog_id: table.catalog_id)
        .update_all(status: "resolved", resolved_at: Time.current, updated_at: Time.current)
    end
  end

  # Whether the status is resolved.
  # @return [Boolean]
  def resolved? = status == "resolved"
end
