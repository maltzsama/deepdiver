require "test_helper"

class MaintenanceScheduleTest < ActiveSupport::TestCase
  test "cannot have two schedules with the same operation on the same table" do
    schedule = build_schedule
    duplicate = build_table.maintenance_schedules.new(operation: "optimize", cron: "0 4 * * *")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:operation], "has already been taken"
  end

  test "rejects a malformed cron expression" do
    schedule = build_table.maintenance_schedules.new(operation: "optimize", cron: "not-a-cron")
    assert_not schedule.valid?
  end

  test "accepts a valid cron and a pause flag" do
    schedule = build_schedule(is_paused: true)
    assert schedule.valid?
    assert schedule.paused?
  end

  test "validates optimize config threshold format" do
    schedule = build_table.maintenance_schedules.new(operation: "optimize", cron: "0 3 * * *",
                                                     config: { "file_size_threshold" => "banana" })

    assert_not schedule.valid?
    assert_includes schedule.errors[:config], "file_size_threshold must be a size string"
  end

  test "ignores empty config values from the form" do
    schedule = build_table.maintenance_schedules.new(operation: "expire_snapshots", cron: "0 3 * * *",
                                                     config: { "file_size_threshold" => "",
                                                               "retention_threshold" => "" })

    assert schedule.valid?
    assert_equal({}, schedule.config)
  end
end
