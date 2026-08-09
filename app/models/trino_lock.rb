class TrinoLock < ApplicationRecord
  GLOBAL_KEY = "global"

  validates :key, presence: true, uniqueness: true

  # Acquire the exclusive Trino lock. Returns the lock instance when the caller
  # becomes the owner, false when another execution holds it. A stale lock whose
  # owner already finished is stolen so a crashed process cannot block forever.
  def self.acquire(execution_history_id, attempts: 0)
    lock = new(key: GLOBAL_KEY, owner: execution_history_id.to_s, acquired_at: Time.current)
    lock.save!
    lock
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    if attempts.zero? && recover_orphaned_lock!
      acquire(execution_history_id, attempts: attempts + 1)
    else
      false
    end
  end

  def self.release(execution_history_id:)
    where(key: GLOBAL_KEY, owner: execution_history_id.to_s).delete_all
  end

  # Steals the lock if the owning execution reached a terminal state.
  def self.recover_orphaned_lock!
    lock = find_by(key: GLOBAL_KEY)
    return false unless lock

    owner = ExecutionHistory.find_by(id: lock.owner)
    return false unless owner&.finished?

    lock.delete
    true
  end
end
