class AddTraitsToSpecimenAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :specimen_assets, :sex, :string
    add_column :specimen_assets, :life_stage, :string
    add_column :specimen_assets, :morph, :string
    add_column :specimen_assets, :view, :string
    add_column :specimen_assets, :part, :string
    add_column :specimen_assets, :region, :string
    add_column :specimen_assets, :notes, :text

    # Indexes for filtering
    add_index :specimen_assets, :sex
    add_index :specimen_assets, :life_stage
    add_index :specimen_assets, :part
    add_index :specimen_assets, :view
  end
end
