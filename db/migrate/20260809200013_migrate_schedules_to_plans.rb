class MigrateSchedulesToPlans < ActiveRecord::Migration[8.1]
  def up
    say_with_time "converting schedules into plans" do
      IcebergTable.find_each do |table|
        schedules = MaintenanceSchedule.where(iceberg_table_id: table.id).to_a
        next if schedules.empty?

        crons = schedules.map(&:cron).uniq
        base = schedules.find { |s| s.operation == "optimize" } ||
               MaintenancePlan::CANONICAL_ORDER.filter_map { |op| schedules.find { |s| s.operation == op } }.first

        plan = MaintenancePlan.create!(
          iceberg_table_id: table.id,
          cron: base.cron,
          is_paused: schedules.all?(&:is_paused),
          consecutive_failures: schedules.map(&:consecutive_failures).max,
          maintenance_policy_id: schedules.map(&:maintenance_policy_id).compact.first,
          needs_review: crons.size > 1
        )

        MaintenancePlan::CANONICAL_ORDER.each_with_index do |operation, index|
          existing = schedules.find { |s| s.operation == operation }
          MaintenanceStep.create!(
            maintenance_plan: plan,
            operation: operation,
            position: index,
            enabled: existing.present? && !existing.is_paused,
            config: existing&.config || {}
          )
        end

        ExecutionHistory.where(maintenance_schedule_id: schedules.map(&:id))
                        .update_all(maintenance_plan_id: plan.id)
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
