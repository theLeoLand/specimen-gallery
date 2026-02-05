class CreateSpecimenAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :specimen_assets do |t|
      t.string :scientific_name
      t.string :common_name
      t.string :taxon_source
      t.string :taxon_id
      t.string :license
      t.string :attribution_name
      t.string :attribution_url
      t.string :status
      t.jsonb :qc_flags

      t.timestamps
    end
  end
end
