class AddEmbeddingToSpecimenAssets < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    add_column :specimen_assets, :embedding, :vector, limit: 384
    add_index :specimen_assets, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
