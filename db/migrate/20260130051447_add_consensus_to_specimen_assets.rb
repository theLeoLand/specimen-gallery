class AddConsensusToSpecimenAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :specimen_assets, :id_status, :string, default: "unverified", null: false
    add_column :specimen_assets, :confirm_count, :integer, default: 0, null: false
    add_column :specimen_assets, :suggest_count, :integer, default: 0, null: false
    add_column :specimen_assets, :top_suggested_taxon_id, :bigint
    add_column :specimen_assets, :top_suggested_count, :integer, default: 0, null: false

    add_index :specimen_assets, :id_status
    add_index :specimen_assets, :top_suggested_taxon_id
    add_foreign_key :specimen_assets, :taxa, column: :top_suggested_taxon_id
  end
end
