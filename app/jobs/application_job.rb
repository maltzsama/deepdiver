# Base class for all background jobs in the application.
class ApplicationJob < ActiveJob::Base
  retry_on ActiveRecord::Deadlocked, wait: 1.second, attempts: 3
  retry_on TrinoEngineSupervisor::ConcurrentTransitionError, wait: 2.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError
end
