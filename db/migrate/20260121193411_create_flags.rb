class CreateFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :flags do |t|
      t.references :specimen_asset, null: false, foreign_key: true
      t.string :reason, null: false
      t.text :details
      t.string :status, null: false, default: "open"
      t.string :reporter_ip

      t.timestamps
    end

    add_index :flags, :status
    add_index :flags, [ :specimen_asset_id, :status ]
  end
end
