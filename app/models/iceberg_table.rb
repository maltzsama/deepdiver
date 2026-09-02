# A table in a catalog discovered or registered by the application. Tracks the
# table's health, freshness history, maintenance schedules, and executions.
class IcebergTable < ApplicationRecord
  # Raised when a SQL identifier is requested for a table Trino cannot name:
  # a table at the catalog root, where there is no schema to address -
  # Trino's identifier is catalog.schema.table with no two-part form.
  #
  # Nested namespaces are NOT a cause: every catalog projects to Trino via
  # the REST connector, which splits the dotted schema under
  # nested-namespace-enabled (see #238).
  #
  # Kept under the original name so existing rescues keep working.
  class NotAddressableInTrino < StandardError; end
  RootTableNotAddressable = NotAddressableInTrino

  HEALTH_STATUSES = %w[unknown healthy warning critical].freeze

  belongs_to :catalog, counter_cache: true

  has_one :maintenance_plan, dependent: :destroy
  has_one :table_freshness_sla, dependent: :destroy
  has_one :latest_freshness_check, -> { order(checked_at: :desc) }, class_name: "FreshnessCheck"
  has_many :freshness_checks, dependent: :destroy
  has_many :execution_histories, dependent: :destroy

  enum :health_status, HEALTH_STATUSES.to_h { |s| [ s, s ] }

  validates :name, presence: true
  # A blank namespace is legitimate: Nessie (and Iceberg generally) permits
  # tables at the repository root. The column stays NOT NULL - "" is the root,
  # nil is missing data - so presence cannot be asserted here.
  validates :namespace, exclusion: { in: [ nil ] }
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

  # The attributes that persist a HealthEvaluator result.
  #
  # ONE writer shape for every caller, so the score, the status label and the
  # component breakdown are always written together from a single evaluation.
  # Recomputing on read is what let the list and the detail page disagree on
  # both the score and the label (see #215); persisting the breakdown lets the
  # detail page render by reading, so a divergence cannot arise.
  #
  # An unscoreable table still records that it WAS evaluated: the breakdown and
  # the timestamp are written while the score and label are left untouched.
  # Without that, health_components stayed blank and the detail page treated
  # the table as never-evaluated and re-evaluated it on every single render -
  # the very thing this exists to prevent.
  #
  # @param health [Hash] a HealthEvaluator.evaluate result
  # @param at [Time] the evaluation clock
  # @return [Hash] attributes to assign
  def health_attributes(health, at: Time.current)
    return { health_components: serialize_health_components(health), health_evaluated_at: at } if health[:score].nil?

    attributes = {
      health_score: health[:score],
      health_status: health[:status].to_s,
      health_components: serialize_health_components(health),
      health_evaluated_at: at
    }
    # Only stamp when the state actually CHANGES. Stamping on every sync would
    # reset the clock and make "broke most recently" ordering just sync order.
    attributes[:health_status_changed_at] = at if attributes[:health_status] != health_status
    attributes
  end

  # The persisted breakdown, in the shape HealthEvaluator.evaluate returns, so
  # the view renders a read and a fresh evaluation identically.
  #
  # @return [Hash, nil] the evaluation shape, or nil when nothing is persisted
  def persisted_health_evaluation
    return nil if health_components.blank?

    stored = health_components
    components = (stored["components"] || {}).transform_keys(&:to_sym)
    {
      score: health_score,
      # An unscoreable table keeps whatever label it last had, but the panel
      # must render :unknown rather than a stale badge with no score behind it.
      status: health_score.nil? ? :unknown : health_status.to_sym,
      components: components,
      coverage: stored["coverage"],
      worst_component: stored["worst_component"]&.to_sym,
      worst_ratio: stored["worst_ratio"],
      details: (stored["details"] || {}).transform_keys(&:to_sym),
      evaluated_at: health_evaluated_at
    }
  end

  # The three-part identifier: catalog.namespace.table.
  #
  # Uses trino_catalog_name rather than the catalog's display name, because
  # trino_catalog_name_override means the two can differ and only the former
  # resolves in Trino - the value is presented as an identifier, so it should
  # be the resolvable one.
  #
  # A table at the repository root has a blank namespace and renders as
  # catalog.table, without the empty middle part that a plain join produces.
  #
  # Display only. trino_identifier / trino_metadata_table build their own
  # quoted identifiers for SQL and never call this.
  #
  # @return [String]
  def fully_qualified_name
    [ catalog&.trino_catalog_name, namespace.presence, name ].compact.join(".")
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
  #
  # A dotted namespace stays inside ONE quoted part. Trino's identifier model
  # is strictly three levels, and the Iceberg connector represents a nested
  # namespace as a single dotted schema name, splitting it internally on its
  # separator. Emitting "cat"."a"."b"."tbl" would be a four-part reference the
  # grammar does not accept - it must not be "corrected" into one (see #227).
  #   "catalog"."ns1.ns2.ns3"."table"
  #
  # A table at the repository root has no schema to address, so there is no
  # valid three-part identifier for it: an empty middle part ("cat".""."tbl")
  # names a schema that cannot exist. Raise rather than emit SQL that fails
  # later with an opaque resolution error.
  #
  # @raise [RootTableNotAddressable] when the table has no namespace
  def trino_identifier
    ensure_addressable!
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
    ensure_addressable!
    [ catalog.trino_catalog_name, namespace, "#{name}$#{suffix}" ]
      .map { |part| quote_identifier(part) }.join(".")
  end

  # Whether this table can be named in a Trino statement at all.
  #
  # Callers that need to know BEFORE acting - the UI, plan creation - should
  # ask this rather than rescuing an exception.
  #
  # @return [Boolean]
  def addressable_in_trino?
    unaddressable_reason.nil?
  end

  # Why Trino cannot name this table, or nil when it can.
  #
  # One structural case: :root - no namespace at all, so there is no schema
  # for Trino's three-part identifier to address. Nested namespaces are fine
  # on every catalog: the projection routes them all through the REST
  # connector, which splits the dotted schema (see #238).
  #
  # @return [Symbol, nil]
  def unaddressable_reason
    return :root if namespace.blank?

    nil
  end

  # The Trino identifier for DISPLAY, or nil when there is none.
  #
  # Execution paths must keep using trino_identifier and let
  # RootTableNotAddressable propagate - a statement built for an unaddressable
  # table has to fail. A read-only field rendering the same value must not,
  # which is what took the detail page down for every root table.
  #
  # @return [String, nil]
  def trino_identifier_for_display
    addressable_in_trino? ? trino_identifier : nil
  end

  private

  # Flattens an evaluation into the JSON column. The component ratios AND the
  # raw numbers behind them are stored, because the breakdown panel needs both
  # and the raw numbers come from the extractor, which is not available on a
  # read path.
  #
  # @param health [Hash] a HealthEvaluator.evaluate result
  # @return [Hash] the JSON-serialisable breakdown
  def serialize_health_components(health)
    {
      "components" => (health[:components] || {}).transform_keys(&:to_s),
      "coverage" => health[:coverage],
      "worst_component" => health[:worst_component]&.to_s,
      "worst_ratio" => health[:worst_ratio],
      "details" => (health[:details] || {}).transform_keys(&:to_s)
    }
  end

  # Guards identifier construction for a table with no namespace.
  #
  # @raise [RootTableNotAddressable] when the namespace is blank
  def ensure_addressable!
    return if unaddressable_reason.nil?

    raise NotAddressableInTrino,
          "#{fully_qualified_name} lives at the catalog root and has no schema to address in Trino"
  end

  # Quotes an identifier for use inside a Trino SQL statement, escaping any
  # embedded double quotes.
  # @param part [String] the identifier part to quote
  # @return [String] the quoted identifier
  def quote_identifier(part)
    %("#{part.to_s.gsub('"', '""')}")
  end
end
