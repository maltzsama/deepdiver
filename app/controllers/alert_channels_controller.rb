# Manages alert channels: where alert notifications go (Slack #channel and/or
# Email recipients) and how often. Each action authorizes with Pundit.
class AlertChannelsController < ApplicationController
  before_action :set_channel, only: %i[show edit update destroy test]

  # Lists all alert channels, ordered by name.
  def index
    authorize AlertChannel
    @channels = AlertChannel.order(:name)
  end

  # Shows a single alert channel.
  def show
    authorize @channel
  end

  # Renders the form for creating a channel.
  def new
    authorize AlertChannel
    @channel = AlertChannel.new
  end

  # Creates a channel and redirects to the list, or re-renders the form.
  def create
    authorize AlertChannel
    @channel = AlertChannel.new(channel_params)
    if @channel.save
      redirect_to alert_channels_path, notice: t("alert_channels.notices.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Renders the edit form for a channel.
  def edit
    authorize @channel
  end

  # Updates the channel and redirects to it, or re-renders the form on failure.
  def update
    authorize @channel
    if @channel.update(channel_params)
      redirect_to alert_channel_path(@channel), notice: t("alert_channels.notices.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Destroys the channel and redirects to the list.
  def destroy
    authorize @channel
    @channel.destroy
    redirect_to alert_channels_path, notice: t("alert_channels.notices.destroyed")
  end

  # Sends a test alert through the channel, bypassing the cooldown.
  def test
    authorize @channel
    AlertChannelNotifier.new(
      subject: t("alert_channels.test.subject"),
      message: t("alert_channels.test.message"),
      severity: "warning",
      context: { test: true }
    ).deliver_to!(@channel)
    redirect_to alert_channels_path, notice: t("alert_channels.notices.test_sent", name: @channel.name)
  end

  private

  # Loads the channel for the current request.
  def set_channel
    @channel = AlertChannel.find(params[:id])
  end

  # Strong parameters for an alert channel.
  def channel_params
    params.require(:alert_channel).permit(:name, :slack_channel, :email_to,
                                          :min_severity, :cooldown_minutes,
                                          :message_template, :enabled)
  end
end
