class AddGroupToTaxa < ActiveRecord::Migration[8.1]
  def change
    add_column :taxa, :group, :string
    add_index :taxa, :group
  end
end
