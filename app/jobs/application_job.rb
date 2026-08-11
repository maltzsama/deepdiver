# Base class for all background jobs in the application. Provides the default
# queue configuration and the commented-out retry/discard behaviour that every
# job inherits.
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
