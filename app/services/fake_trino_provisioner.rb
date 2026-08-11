# In-memory provisioner for development and tests. Immediately "exists" and
# healthy after create!, and always idle, so the whole engine state machine
# runs without a cluster.
class FakeTrinoProvisioner
  # Starts with the engine absent and unhealthy.
  def initialize
    @exists = false
    @healthy = false
  end

  # Whether the fake engine "exists".
  #
  # @return [Boolean] true after create! has been called
  def exists? = @exists

  # Whether the fake engine is "healthy".
  #
  # @return [Boolean] true after create! has been called
  def healthy? = @healthy

  # Whether the fake rollout is complete.
  #
  # @return [Boolean] true once the engine exists
  def rollout_complete? = @exists

  # The fake engine is always idle.
  #
  # @return [Boolean] always true
  def idle? = true

  # Marks the fake engine as existing and healthy.
  def create!
    @exists = true
    @healthy = true
  end

  # Marks the fake engine as gone and unhealthy.
  def destroy!
    @exists = false
    @healthy = false
  end

  # No-op: the fake engine disappears instantly.
  #
  # @param timeout [ActiveSupport::Duration] ignored
  def wait_gone!(timeout:)
  end
end
