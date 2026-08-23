# Edits the freshness SLA of one table: which watermark column to probe, how
# stale the table may get, and the progressive severity bands for alerts. The
# SLA row is created on first save; every action authorizes with Pundit.
class FreshnessSlasController < ApplicationController
  before_action :set_table
  before_action :set_sla

  # Renders the edit form for the table's SLA.
  def edit
    authorize @sla
  end

  # Creates or updates the SLA and redirects back to the table.
  def update
    authorize @sla
    if @sla.update(sla_params)
      redirect_to @table, notice: t("freshness_slas.notices.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  # Loads the table from the nested route.
  def set_table
    @table = IcebergTable.find(params[:iceberg_table_id])
  end

  # Loads the table's SLA, or an empty draft to be created on save.
  def set_sla
    @sla = @table.table_freshness_sla || @table.build_table_freshness_sla(
      timestamp_type: "timestamp_tz", source_timezone: "UTC",
      partition_lookback: 7, warning_at_percent: 80
    )
  end

  # Strong parameters for a freshness SLA.
  def sla_params
    params.require(:table_freshness_sla).permit(
      :enabled, :timestamp_column, :timestamp_type, :source_timezone,
      :partition_column, :partition_lookback, :sla_minutes, :warning_at_percent,
      :warning_after_minutes, :severe_after_minutes, :critical_after_minutes,
      :slack_channel, :email_to
    )
  end
end
