class AddGbifFieldsToTaxaAndNeedsReviewToSpecimenAssets < ActiveRecord::Migration[8.1]
  def change
    # GBIF fields on taxa
    add_column :taxa, :gbif_key, :integer
    add_column :taxa, :gbif_rank, :string
    add_column :taxa, :gbif_canonical_name, :string
    add_column :taxa, :gbif_confidence, :integer
    add_column :taxa, :gbif_match_type, :string

    add_index :taxa, :gbif_key

    # Review flag on specimen_assets
    add_column :specimen_assets, :needs_review, :boolean, default: false, null: false

    add_index :specimen_assets, :needs_review
  end
end
