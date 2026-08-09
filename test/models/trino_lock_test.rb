require "test_helper"

class TrinoLockTest < ActiveSupport::TestCase
  test "acquire returns the lock and a second acquire returns false" do
    first = TrinoLock.acquire(999)
    assert_kind_of TrinoLock, first
    assert_equal 999, first.execution_history_id

    assert_equal false, TrinoLock.acquire(22)
  end

  test "release only removes the lock owned by that execution" do
    TrinoLock.acquire(11)
    assert_equal 1, TrinoLock.count

    TrinoLock.release(execution_history_id: 11)
    assert_equal 0, TrinoLock.count
    assert TrinoLock.acquire(33)
  end

  test "release is a no-op for a lock held by another execution" do
    TrinoLock.acquire(11)
    TrinoLock.release(execution_history_id: 22)

    assert_equal 1, TrinoLock.count
  end

  test "a stale lock whose owner already finished is stolen" do
    schedule = build_schedule
    finished = schedule.execution_histories.create!(status: :success)
    fresh = schedule.execution_histories.create!(status: :running)
    TrinoLock.acquire(finished.id)

    assert TrinoLock.acquire(fresh.id)

    assert_equal fresh.id, TrinoLock.first.execution_history_id
  end
end
