module MaintenanceOrchestrator
  # Maps the orchestration interface onto Active Job / Solid Queue.
  # Backoff is expressed with `set(wait:)`, never by sleeping inside a job.
  class SolidQueueBackend < Backend
    def start_execution(execution_history_id)
      TrinoManagerJob.perform_later(execution_history_id)
    end

    def retry_lock_acquisition(execution_history_id)
      TrinoManagerJob.set(wait: 5.minutes).perform_later(execution_history_id)
    end

    def scale_up(execution_history_id)
      ScaleUpJob.perform_later(execution_history_id)
    end

    def retry_scale_up(execution_history_id)
      ScaleUpJob.set(wait: 15.seconds).perform_later(execution_history_id)
    end

    def execute_maintenance(execution_history_id)
      ExecuteMaintenanceJob.perform_later(execution_history_id)
    end

    def retry_maintenance(execution_history_id)
      ExecuteMaintenanceJob.set(wait: 10.minutes).perform_later(execution_history_id)
    end

    def scale_down(execution_history_id)
      ScaleDownJob.perform_later(execution_history_id)
    end

    def sync_catalog(catalog_id, force: false)
      CatalogSyncJob.perform_later(catalog_id, force: force)
    end
  end
end
