module MaintenanceOrchestrator
  # Port (hexagonal): the only way the application talks to a job queue. The
  # rest of the codebase never refers to specific job classes, so we can swap
  # the transport (Solid Queue, Temporal, ...) by exchanging the implementation.
  class Backend
    def start_execution_on_engine(execution_history_id) = raise NotImplementedError
    def retry_lock_acquisition(execution_history_id) = raise NotImplementedError
    def supervise_engine_start = raise NotImplementedError
    def drain_engine = raise NotImplementedError
    def execute_maintenance(execution_history_id) = raise NotImplementedError
    def retry_maintenance(execution_history_id) = raise NotImplementedError
    def start_freshness_sweep(freshness_run_id) = raise NotImplementedError
    def sync_catalog(catalog_id, force:) = raise NotImplementedError
  end
end
