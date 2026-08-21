# Manages the singleton engine configuration: how the ephemeral Trino engine is
# materialised on the next start (single-node vs coordinator + workers) and the
# CPU/memory of each node. Each action authorizes with Pundit.
class TrinoEngineConfigsController < ApplicationController
  # Shows the engine configuration form.
  def show
    authorize TrinoEngineConfig
    @config = TrinoEngineConfig.instance
  end

  # Updates the engine configuration and redirects back, or re-renders on error.
  # When the engine is currently running, the new settings are applied to the
  # live cluster immediately (worker replicas, node resources, coordinator env).
  def update
    authorize TrinoEngineConfig
    @config = TrinoEngineConfig.instance
    was_up = TrinoEngineState.first&.status == "up"
    if @config.update(config_params)
      apply_to_running_cluster! if was_up
      key = was_up ? "trino_engine_config.notices.updated_and_applied" : "trino_engine_config.notices.updated"
      redirect_to trino_engine_config_path, notice: t(key)
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  # Strong parameters for the engine configuration.
  def config_params
    params.require(:trino_engine_config).permit(
      :topology, :worker_replicas, :coordinator_cpu, :coordinator_memory, :worker_cpu, :worker_memory
    )
  end

  # Applies the current config to the live Trino cluster when the engine is up.
  # This patches coordinator resources and env (for topology changes) and scales
  # the worker deployment to the configured replica count. The pods will be
  # restarted by Kubernetes if resources change.
  def apply_to_running_cluster!
    provisioner = TrinoProvisioner.adapter
    config = TrinoEngineConfig.instance
    provisioner.send(:apply_coordinator_spec)
    provisioner.send(:apply_worker_spec) if config.cluster?
  rescue StandardError => e
    Rails.logger.warn("Failed to apply engine config live: #{e.message}")
  end
end
