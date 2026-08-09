class RenameRewriteManifestsOperation < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE maintenance_schedules SET operation = 'optimize_manifests'
      WHERE operation = 'rewrite_manifests'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE maintenance_schedules SET operation = 'rewrite_manifests'
      WHERE operation = 'optimize_manifests'
    SQL
  end
end
