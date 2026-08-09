module MaintenanceOrchestrator
  # Maps the orchestration interface onto Active Job / Solid Queue.
  # Backoff is expressed with `set(wait:)`, never by sleeping inside a job.
  class SolidQueueBackend < Backend
    def start_execution_on_engine(execution_history_id)
      StartExecutionOnEngineJob.perform_later(execution_history_id)
    end

    def retry_lock_acquisition(execution_history_id)
      StartExecutionOnEngineJob.set(wait: 5.minutes).perform_later(execution_history_id)
    end

    def supervise_engine_start
      SuperviseEngineStartJob.perform_later
    end

    def drain_engine
      DrainEngineJob.perform_later
    end

    def execute_maintenance(execution_history_id)
      ExecuteMaintenanceJob.perform_later(execution_history_id)
    end

    def retry_maintenance(execution_history_id)
      ExecuteMaintenanceJob.set(wait: 10.minutes).perform_later(execution_history_id)
    end

    def start_freshness_sweep(freshness_run_id)
      FreshnessSweepJob.perform_later(freshness_run_id)
    end

    def sync_catalog(catalog_id, force: false)
      CatalogSyncJob.perform_later(catalog_id, force: force)
    end
  end
end
