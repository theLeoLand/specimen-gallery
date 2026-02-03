class RenameContestedToMixed < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE specimen_assets SET id_status = 'mixed' WHERE id_status = 'contested'"
  end

  def down
    execute "UPDATE specimen_assets SET id_status = 'contested' WHERE id_status = 'mixed'"
  end
end
