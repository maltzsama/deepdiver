module ApplicationHelper
  STEP_LABELS = {
    "start"         => "lock",
    "scale_up"      => "scale up",
    "executing_sql" => "SQL",
    "scale_down"    => "scale down",
    "done"          => "done"
  }.freeze

  def step_label(step)
    STEP_LABELS.fetch(step.to_s, step.to_s)
  end

  # Visual state of an execution, including the retry created for commit
  # conflicts. Returns :retrying, :failed or :running.
  def execution_visual_state(execution)
    return :failed if execution.status == "failed"
    return :retrying if execution.respond_to?(:awaiting_retry) && execution.awaiting_retry?

    :running
  end
end
