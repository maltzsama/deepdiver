# Solid Queue adapter for the maintenance orchestrator.
module MaintenanceOrchestrator
  # Maps the orchestration interface onto Active Job / Solid Queue.
  # Backoff is expressed with `set(wait:)`, never by sleeping inside a job.
  class SolidQueueBackend < Backend
    # Enqueues StartExecutionOnEngineJob immediately.
    #
    # @param execution_history_id [Integer] the execution to start
    def start_execution_on_engine(execution_history_id)
      StartExecutionOnEngineJob.perform_later(execution_history_id)
    end

    # Enqueues StartExecutionOnEngineJob after a 5-minute backoff.
    #
    # @param execution_history_id [Integer] the execution to retry
    def retry_lock_acquisition(execution_history_id)
      StartExecutionOnEngineJob.set(wait: 5.minutes).perform_later(execution_history_id)
    end

    # Enqueues SuperviseEngineStartJob.
    def supervise_engine_start
      SuperviseEngineStartJob.perform_later
    end

    # Enqueues DrainEngineJob.
    def drain_engine
      DrainEngineJob.perform_later
    end

    # Enqueues ExecuteMaintenanceJob.
    #
    # @param execution_history_id [Integer] the execution to run
    def execute_maintenance(execution_history_id)
      ExecuteMaintenanceJob.perform_later(execution_history_id)
    end

    # Enqueues ExecuteMaintenanceJob after a 10-minute backoff.
    #
    # @param execution_history_id [Integer] the execution to retry
    def retry_maintenance(execution_history_id)
      ExecuteMaintenanceJob.set(wait: 10.minutes).perform_later(execution_history_id)
    end

    # Enqueues FreshnessSweepJob.
    #
    # @param freshness_run_id [Integer] the run to start
    def start_freshness_sweep(freshness_run_id)
      FreshnessSweepJob.perform_later(freshness_run_id)
    end

    # Enqueues CatalogSyncJob.
    #
    # @param catalog_id [Integer] the catalog to sync
    # @param force [Boolean] whether to force a full resync
    def sync_catalog(catalog_id, force: false)
      CatalogSyncJob.perform_later(catalog_id, force: force)
    end
  end
end
