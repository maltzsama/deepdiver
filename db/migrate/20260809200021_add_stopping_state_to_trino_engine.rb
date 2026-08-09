class AddStoppingStateToTrinoEngine < ActiveRecord::Migration[8.1]
  def change
    # Generation: bumped on every transition. Lets the drain job detect that
    # the world changed underneath it.
    add_column :trino_engine_states, :generation, :bigint, null: false, default: 0
  end
end
