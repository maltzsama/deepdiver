class AddSingletonConstraints < ActiveRecord::Migration[8.0]
  def change
    # Each of these tables is a singleton (one row, read-then-insert without a
    # unique guard). The bootstrap window — while the table is empty — let two
    # concurrent processes each insert a row, defeating the engine row-lock
    # mutex that TrinoEngineSupervisor's correctness depends on.
    #
    # A singleton_key column with a unique index makes the single-row contract
    # hold at the database level: the first insert wins, subsequent ones violate
    # the constraint and the first_or_create! retry loop converges.
    {
      alert_settings:       "alert_settings_singleton",
      trino_engine_configs: "trino_engine_configs_singleton",
      trino_engine_states:  "trino_engine_states_singleton"
    }.each do |table, index_name|
      add_column table, :singleton_key, :integer, default: 1, null: false
      add_index table, :singleton_key, unique: true, name: index_name
    end
  end
end
