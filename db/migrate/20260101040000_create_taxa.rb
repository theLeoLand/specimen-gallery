class CreateTaxa < ActiveRecord::Migration[8.1]
  def change
    create_table :taxa do |t|
      t.string :scientific_name, null: false
      t.string :taxon_source
      t.string :taxon_id
      t.string :rank

      t.timestamps
    end

    add_index :taxa, "LOWER(scientific_name)", unique: true, name: "index_taxa_on_lower_scientific_name"
  end
end
