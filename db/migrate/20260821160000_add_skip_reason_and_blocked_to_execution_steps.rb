class AddSkipReasonAndBlockedToExecutionSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :execution_steps, :skip_reason, :string

    reversible do |dir|
      dir.up do
        # skip_reason takes over configuration reasons; error_message becomes
        # operational-failure-only. Safe because for skipped steps the column
        # only ever held a skip reason.
        execute <<~SQL
          UPDATE execution_steps SET skip_reason = error_message, error_message = NULL
          WHERE status = 'skipped' AND error_message IS NOT NULL
        SQL

        # Pending steps inside a terminal execution never ran and never will:
        # they were left behind when the chain aborted. Restrict to terminal
        # executions - pending under a running execution is legitimate demand.
        execute <<~SQL
          UPDATE execution_steps SET status = 'blocked', skip_reason = 'chain aborted'
          WHERE status = 'pending' AND execution_history_id IN (
            SELECT id FROM execution_histories WHERE status IN ('failed', 'success', 'skipped')
          )
        SQL
      end
    end
  end
end
