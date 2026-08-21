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
  def update
    authorize TrinoEngineConfig
    @config = TrinoEngineConfig.instance
    if @config.update(config_params)
      redirect_to trino_engine_config_path, notice: t("trino_engine_config.notices.updated")
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
end
