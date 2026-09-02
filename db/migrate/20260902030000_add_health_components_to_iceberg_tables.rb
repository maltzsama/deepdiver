class AddHealthComponentsToIcebergTables < ActiveRecord::Migration[8.0]
  def change
    # The health breakdown is persisted alongside the score it explains, so the
    # detail page can render the panel by READING rather than re-evaluating.
    # Recomputing on read is what let the list and the detail disagree on both
    # the score and the status label (see #215): two independent evaluations
    # diverge the moment HealthEvaluator changes, with no code change needed to
    # trigger it.
    add_column :iceberg_tables, :health_components, :json
    add_column :iceberg_tables, :health_evaluated_at, :datetime
  end
end
