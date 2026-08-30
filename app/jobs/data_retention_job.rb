# Prunes old application data to keep the database from growing unbounded.
# Runs daily in production.
#
# After the cascade FK migration, execution_histories can be deleted without
# worrying about orphaned steps or locks. TableLock.reap_stale! runs first
# to clean up any stale locks before the main pruning pass.
class DataRetentionJob < ApplicationJob
  queue_as :default

  DEFAULT_RETENTION = {
    error_events: 90.days,
    execution_histories: 90.days,
    execution_steps: 90.days,
    freshness_checks: 30.days,
    freshness_runs: 30.days,
    # Key name drives the env override: SOLID_QUEUE_RETENTION_DAYS.
    solid_queue: 7.days
  }.freeze

  # Explicit table map — no constantize, no rescue NameError.
  KLASSES = {
    error_events: ErrorEvent,
    execution_histories: ExecutionHistory,
    execution_steps: ExecutionStep,
    freshness_checks: FreshnessCheck,
    freshness_runs: FreshnessRun
  }.freeze

  # Which column decides "old". ErrorEvent dedupes by message: a recurring
  # failure keeps its original created_at and only bumps last_seen_at, so
  # pruning it by created_at deleted OPEN errors that were still happening -
  # exactly the ones worth keeping. The schema's [status, last_seen_at] index
  # points at the right column.
  TIMESTAMP_COLUMNS = {
    error_events: :last_seen_at
  }.freeze
  DEFAULT_TIMESTAMP_COLUMN = :created_at

  BATCH_SIZE = 5_000

  def perform
    TableLock.reap_stale!

    KLASSES.each do |key, klass|
      prune(key, klass)
    end

    prune_solid_queue
  rescue StandardError => e
    ErrorEvent.record(catalog: nil, schema: "retention", operation: "data-retention",
                      source_system: "app", error_class: e.class.name, message: e.message)
    raise
  end

  private

  def prune(key, klass)
    cutoff = retention_cutoff(key)
    column = TIMESTAMP_COLUMNS.fetch(key, DEFAULT_TIMESTAMP_COLUMN)

    loop do
      deleted = klass.where(column => ...cutoff).limit(BATCH_SIZE).delete_all
      Rails.logger.info("DataRetention: deleted #{deleted} #{key} by #{column}") if deleted.positive?
      break if deleted.zero?
    end
  end

  # Retention window for a key: the <KEY>_RETENTION_DAYS override, else the
  # DEFAULT_RETENTION entry.
  #
  # @param key [Symbol] the retention key
  # @return [ActiveSupport::TimeWithZone] the cutoff instant
  def retention_cutoff(key)
    default_days = DEFAULT_RETENTION.fetch(key) / 1.day
    raw = ENV["#{key.to_s.upcase}_RETENTION_DAYS"]
    days = Integer(raw, exception: false) if raw.present?
    if raw.present? && (days.nil? || days <= 0)
      Rails.logger.warn("DataRetention: ignoring invalid #{key.to_s.upcase}_RETENTION_DAYS=#{raw.inspect}; using default #{default_days}d")
      days = nil
    end
    (days || default_days).days.ago
  end

  def prune_solid_queue
    cutoff = retention_cutoff(:solid_queue)

    loop do
      deleted = SolidQueue::Job.where.not(finished_at: nil)
                               .where(finished_at: ...cutoff)
                               .limit(BATCH_SIZE).delete_all
      Rails.logger.info("DataRetention: deleted #{deleted} finished Solid Queue jobs") if deleted.positive?
      break if deleted.zero?
    end
  rescue ActiveRecord::StatementInvalid
    nil
  end
end
