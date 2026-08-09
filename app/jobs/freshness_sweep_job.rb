# One run per hour over every enabled SLA. The cost of bringing the engine up
# is amortised across all tables. Own queue: freshness cannot sit behind a
# 40-minute optimize.
class FreshnessSweepJob < ApplicationJob
  queue_as :freshness

  def perform(freshness_run_id)
    run = FreshnessRun.find(freshness_run_id)
    run.update!(status: "running", started_at: Time.current)

    slas = TableFreshnessSla.where(enabled: true).includes(iceberg_table: :catalog)

    checked = late = errored = 0

    slas.find_each do |sla|
      result = FreshnessProbe.new(sla).call
      record_check(sla, result)
      FreshnessAlerter.new(sla, result).call

      checked += 1
      late    += 1 if result.status == "late"
      errored += 1 if result.status == "error"
    rescue StandardError => e
      # A problematic table does not take the whole sweep down. It shows as
      # 'error' in the history instead of silently disappearing.
      errored += 1
      record_check(sla, FreshnessProbe::Result.new(status: "error", error_message: e.message))
      Rails.logger.error("Freshness failed for #{sla.iceberg_table_id}: #{e.message}")
    end

    run.update!(status: "finished", finished_at: Time.current,
                tables_checked: checked, tables_late: late, tables_errored: errored)
  ensure
    TrinoEngineSupervisor.demand_finished!
  end

  private

  def record_check(sla, result)
    FreshnessCheck.create!(
      iceberg_table_id: sla.iceberg_table_id,
      checked_at: Time.current,
      max_timestamp: result.max_timestamp,
      delay_seconds: result.delay_seconds,
      sla_minutes: sla.sla_minutes,
      status: result.status,
      error_message: result.error_message,
      trino_query_id: result.query_id,
      duration_ms: result.duration_ms
    )
  end
end
