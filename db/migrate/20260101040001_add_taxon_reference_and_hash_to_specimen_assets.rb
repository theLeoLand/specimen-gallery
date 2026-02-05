class AddTaxonReferenceAndHashToSpecimenAssets < ActiveRecord::Migration[8.1]
  def change
    # Remove columns that moved to taxa table FIRST
    remove_column :specimen_assets, :scientific_name, :string
    remove_column :specimen_assets, :taxon_source, :string
    remove_column :specimen_assets, :taxon_id, :string

    # Add new columns (specify table name for irregular plural)
    add_reference :specimen_assets, :taxon, foreign_key: { to_table: :taxa }
    add_column :specimen_assets, :sha256_hash, :string
    add_index :specimen_assets, :sha256_hash, unique: true
  end
end
