class CreateIdVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :id_votes do |t|
      t.references :specimen_asset, null: false, foreign_key: true
      t.references :suggested_taxon, foreign_key: { to_table: :taxa }
      t.string :vote_kind, null: false
      t.string :voter_fingerprint, null: false
      t.string :voter_ip_hash, null: false

      t.timestamps
    end

    # One vote per fingerprint per asset
    add_index :id_votes, [ :specimen_asset_id, :voter_fingerprint ], unique: true
    add_index :id_votes, :voter_ip_hash
  end
end
