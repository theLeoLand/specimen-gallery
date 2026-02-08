class CollapseMixedToUnverified < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE specimen_assets SET id_status = 'unverified' WHERE id_status = 'mixed'"
  end

  def down
    # No safe reversal — mixed status no longer exists
  end
end
