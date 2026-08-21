# Prunes old application data to keep the database from growing unbounded.
# Runs daily in production.
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

  def perform
    prune(:error_events)
    prune(:execution_histories)
    prune(:execution_steps)
    prune(:freshness_checks)
    prune(:freshness_runs)
    prune_solid_queue
  end

  private

  def prune(key)
    klass = key.to_s.classify.constantize
    cutoff = ENV.fetch("#{key.upcase}_RETENTION_DAYS", "#{DEFAULT_RETENTION[key] / 1.day}").to_i.days.ago
    count = klass.where(created_at: ...cutoff).delete_all
    Rails.logger.info("DataRetention: deleted #{count} #{key}") if count.positive?
  rescue NameError, NoMethodError
    nil
  end

  def prune_solid_queue
    days = ENV.fetch("SOLID_QUEUE_RETENTION_DAYS", "7").to_i
    cutoff = days.days.ago
    begin
      count = SolidQueue::Job.where.not(finished_at: nil).where(finished_at: ...cutoff).delete_all
      Rails.logger.info("DataRetention: deleted #{count} finished Solid Queue jobs") if count.positive?
    rescue StandardError
      nil
    end
  end
end
