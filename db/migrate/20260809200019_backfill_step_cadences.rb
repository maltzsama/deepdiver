class BackfillStepCadences < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:maintenance_schedules)

    say_with_time "restoring cadences from legacy schedules" do
      MaintenancePlan.where(needs_review: true).find_each do |plan|
        legacy = select_all(<<~SQL).to_a
          SELECT operation, cron FROM maintenance_schedules
          WHERE iceberg_table_id = #{plan.iceberg_table_id}
        SQL

        by_operation = legacy.to_h { |row| [ row["operation"], row["cron"] ] }
        next if by_operation.values.uniq.size <= 1

        # The plan takes the FINEST cron; each step keeps its own.
        finest = by_operation.values.min_by { |cron| average_interval(cron) }
        plan.update!(cron: finest)

        plan.maintenance_steps.each do |step|
          original = by_operation[step.operation]
          next if original.blank? || original == finest

          step.update!(cadence_cron: original)
        rescue ActiveRecord::RecordInvalid
          # The cadence would never align with the plan cron; leave the plan
          # flagged for manual review instead of writing dead configuration.
          say "  #{plan.iceberg_table_id}/#{step.operation}: cadence #{original.inspect} not aligned - left for review"
          plan.update!(needs_review: true)
        end

        plan.update!(needs_review: false)
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Average interval between dispatches, to find the finest cron.
  def average_interval(cron)
    parsed = Fugit::Cron.parse(cron)
    return Float::INFINITY if parsed.nil?

    from = Time.current
    times = 5.times.each_with_object([]) { |_, acc| from = parsed.next_time(from).to_t; acc << from }
    (times.last - times.first) / (times.size - 1)
  end
end
