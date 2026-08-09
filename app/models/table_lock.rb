class TableLock < ApplicationRecord
  belongs_to :iceberg_table
  belongs_to :execution_history

  # The uniqueness constraint is the real guarantee; the rescue only translates it.
  def self.acquire(execution)
    create!(iceberg_table_id: execution.iceberg_table_id,
            execution_history: execution,
            acquired_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end

  def self.release(execution)
    where(execution_history_id: execution.id).delete_all
  end

  # A lock whose owner finished or disappeared is garbage: free it.
  def self.reap_stale!
    joins(:execution_history)
      .where.not(execution_histories: { status: %w[pending running] })
      .delete_all
  end
end
