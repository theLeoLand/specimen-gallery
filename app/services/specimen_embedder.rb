# Turns specimen names into vectors with the local bge-small model, and finds
# nearby specimens when a search doesn't literally contain those words.
class SpecimenEmbedder
  MODEL_ID = "Xenova/bge-small-en-v1.5"
  QUERY_PREFIX = "Represent this sentence for searching relevant passages: "
  # Cosine distance. Real near-matches on this gallery land around 0.18–0.39.
  # Unrelated lookalikes, like a frog for "ladybug", start around 0.45.
  MAX_DISTANCE = 0.40
  RESULT_LIMIT = 40
  # Stored name against stored name sits closer than a typed search against a name.
  # Two frogs land near 0.25. A honey bee against a frog is already past 0.40.
  RELATED_MAX_DISTANCE = 0.32
  RELATED_LIMIT = 6

  def self.store!(asset)
    text = document_for(asset)
    return if text.blank?

    asset.update_column(:embedding, embed_document(text))
  end

  def self.document_for(asset)
    taxon = asset.taxon
    [
      asset.specimen_name,
      asset.common_name,
      taxon&.scientific_name,
      taxon&.gbif_canonical_name,
      taxon&.group,
      asset.morph,
      asset.region,
      asset.life_stage,
      asset.part,
      asset.sex,
      asset.view
    ].map { |value| value.to_s.strip }.reject(&:blank?).uniq.join(". ")
  end

  def self.matching_taxon_ids(query, taxon_scope:, id_status:)
    vector = embed_query(query)
    return [] if vector.blank?

    assets = SpecimenAsset.where(status: "approved").where(taxon_id: taxon_scope.except(:order).reselect("taxa.id"))
    assets = case id_status
    when "verified" then assets.where(id_status: "verified")
    when "unverified" then assets.where.not(id_status: "verified")
    else assets
    end

    assets.nearest_neighbors(:embedding, vector, distance: "cosine", threshold: MAX_DISTANCE)
      .limit(RESULT_LIMIT)
      .map(&:taxon_id)
      .uniq
  rescue StandardError => e
    Rails.logger.warn("Semantic taxon search failed: #{e.class}: #{e.message}")
    []
  end

  def self.matching_specimen_ids(query, scope:)
    vector = embed_query(query)
    return [] if vector.blank?

    scope.nearest_neighbors(:embedding, vector, distance: "cosine", threshold: MAX_DISTANCE)
      .limit(RESULT_LIMIT)
      .map(&:id)
  rescue StandardError => e
    Rails.logger.warn("Semantic specimen search failed: #{e.class}: #{e.message}")
    []
  end

  # Other approved species whose stored names sit close to this one.
  # One photo per species. Same species is skipped; that page already shows those.
  def self.related_assets(asset, limit: RELATED_LIMIT)
    return [] if asset.nil? || asset.embedding.blank? || asset.taxon_id.blank?

    scope = SpecimenAsset.where(status: "approved")
      .where.not(taxon_id: asset.taxon_id)
      .joins(:image_attachment)
    group = asset.taxon&.group
    scope = scope.joins(:taxon).where(taxa: { group: group }) if group.present? && group != "other"

    candidates = scope.nearest_neighbors(:embedding, asset.embedding, distance: "cosine", threshold: RELATED_MAX_DISTANCE)
      .includes(:taxon, image_attachment: :blob)
      .limit(limit * 8)

    picked = []
    seen_taxa = {}
    candidates.each do |candidate|
      next if seen_taxa[candidate.taxon_id]

      seen_taxa[candidate.taxon_id] = true
      picked << candidate
      break if picked.size >= limit
    end
    picked
  rescue StandardError => e
    Rails.logger.warn("Related specimens failed: #{e.class}: #{e.message}")
    []
  end

  def self.embed_query(text)
    cleaned = text.to_s.strip
    return if cleaned.length < 3
    return if Rails.env.test?

    if defined?(@last_query) && @last_query == cleaned
      return @last_vector
    end

    @last_query = cleaned
    @last_vector = model.call(QUERY_PREFIX + cleaned)
  end

  def self.embed_document(text)
    model.call(text)
  end

  def self.model
    @model ||= Informers.pipeline("embedding", MODEL_ID)
  end
end
