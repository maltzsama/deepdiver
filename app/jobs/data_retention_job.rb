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
    solid_queue_finished: 7.days
  }.freeze

  # Explicit table map — no constantize, no rescue NameError.
  KLASSES = {
    error_events: ErrorEvent,
    execution_histories: ExecutionHistory,
    execution_steps: ExecutionStep,
    freshness_checks: FreshnessCheck,
    freshness_runs: FreshnessRun
  }.freeze

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
    cutoff = ENV.fetch("#{key.to_s.upcase}_RETENTION_DAYS", "#{DEFAULT_RETENTION[key] / 1.day}").to_i.days.ago

    loop do
      deleted = klass.where(created_at: ...cutoff).limit(BATCH_SIZE).delete_all
      Rails.logger.info("DataRetention: deleted #{deleted} #{key}") if deleted.positive?
      break if deleted.zero?
    end
  end

  def prune_solid_queue
    days = ENV.fetch("SOLID_QUEUE_RETENTION_DAYS", "7").to_i
    cutoff = days.days.ago

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
