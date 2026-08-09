module MaintenanceOrchestrator
  # Port (hexagonal): the only way the application talks to a job queue. The
  # rest of the codebase never refers to specific job classes, so we can swap
  # the transport (Solid Queue, Temporal, ...) by exchanging the implementation.
  class Backend
    def start_execution(execution_history_id) = raise NotImplementedError
    def sync_catalog(catalog_id, force:) = raise NotImplementedError
    def retry_lock_acquisition(execution_history_id) = raise NotImplementedError
    def scale_up(execution_history_id) = raise NotImplementedError
    def retry_scale_up(execution_history_id) = raise NotImplementedError
    def execute_maintenance(execution_history_id) = raise NotImplementedError
    def retry_maintenance(execution_history_id) = raise NotImplementedError
    def scale_down(execution_history_id) = raise NotImplementedError
  end
end
