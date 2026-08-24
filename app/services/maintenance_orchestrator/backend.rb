# Job-queue port and adapters used by the maintenance orchestrator.
module MaintenanceOrchestrator
  # Port (hexagonal): the only way the application talks to a job queue. The
  # rest of the codebase never refers to specific job classes, so we can swap
  # the transport (Solid Queue, Temporal, ...) by exchanging the implementation.
  class Backend
    # Dispatches a pending execution onto the engine.
    #
    # @param execution_history_id [Integer] the execution to start
    def start_execution_on_engine(execution_history_id) = raise NotImplementedError
    # Retries acquiring the lock for an execution after a backoff.
    #
    # @param execution_history_id [Integer] the execution to retry
    def retry_lock_acquisition(execution_history_id) = raise NotImplementedError
    # Supervises the engine coming up.
    def supervise_engine_start = raise NotImplementedError
    # Drains the engine after demand finishes.
    def drain_engine = raise NotImplementedError
    # Runs the maintenance chain of an execution.
    #
    # @param execution_history_id [Integer] the execution to run
    def execute_maintenance(execution_history_id) = raise NotImplementedError
    # Retries the maintenance chain of an execution after a backoff.
    #
    # @param execution_history_id [Integer] the execution to retry
    def retry_maintenance(execution_history_id) = raise NotImplementedError
    # Retries the maintenance chain shortly after a dispatch was consumed
    # before the primary status: :running write was visible. Used to close the
    # cross-database race without a long backoff.
    #
    # @param execution_history_id [Integer] the execution to retry
    def retry_pending_maintenance(execution_history_id) = raise NotImplementedError
    # Runs a freshness sweep against the enabled SLAs.
    #
    # @param freshness_run_id [Integer] the run to start
    def start_freshness_sweep(freshness_run_id) = raise NotImplementedError
    # Syncs a catalog's metadata.
    #
    # @param catalog_id [Integer] the catalog to sync
    # @param force [Boolean] whether to force a full resync
    def sync_catalog(catalog_id, force:) = raise NotImplementedError
  end
end
