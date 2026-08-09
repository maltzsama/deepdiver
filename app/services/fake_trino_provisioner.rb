# In-memory provisioner for development and tests. Immediately "exists" and
# healthy after create!, and always idle, so the whole engine state machine
# runs without a cluster.
class FakeTrinoProvisioner
  def initialize
    @exists = false
    @healthy = false
  end

  def exists? = @exists

  def healthy? = @healthy

  def rollout_complete? = @exists

  def idle? = true

  def create!
    @exists = true
    @healthy = true
  end

  def destroy!
    @exists = false
    @healthy = false
  end

  def wait_gone!(timeout:)
  end
end
