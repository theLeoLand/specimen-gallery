class AddCloudinaryFieldsToSpecimenAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :specimen_assets, :bg_removed, :boolean, default: false, null: false
    add_column :specimen_assets, :cloudinary_public_id, :string
    add_column :specimen_assets, :cloudinary_asset_url, :text

    add_index :specimen_assets, :bg_removed
  end
end


