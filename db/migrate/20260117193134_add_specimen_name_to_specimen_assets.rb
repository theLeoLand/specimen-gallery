class AddSpecimenNameToSpecimenAssets < ActiveRecord::Migration[8.1]
  def up
    add_column :specimen_assets, :specimen_name, :string

    # Backfill existing records: use common_name if present, otherwise use taxon's scientific_name
    execute <<-SQL.squish
      UPDATE specimen_assets
      SET specimen_name = COALESCE(
        NULLIF(common_name, ''),
        (SELECT scientific_name FROM taxa WHERE taxa.id = specimen_assets.taxon_id)
      )
    SQL

    # Add index for searching
    add_index :specimen_assets, :specimen_name
  end

  def down
    remove_index :specimen_assets, :specimen_name
    remove_column :specimen_assets, :specimen_name
  end
end
