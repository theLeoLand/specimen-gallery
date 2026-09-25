# app/services/taxon_resolver.rb
# Resolves a scientific name to a Taxon, enriching it with GBIF backbone data.
#
# Shared by the public upload controller and the bulk ingestion pipeline so both
# create taxa identically. Wraps GbifClient (name matching) and
# TaxonGroupResolver (group assignment).
class TaxonResolver
  # Bundles the resolved taxon with the GBIF match context callers need to make
  # review/publish decisions.
  Result = Struct.new(:taxon, :gbif_match, :good_match, keyword_init: true) do
    def good_match?
      good_match
    end
  end

  # Match a name against GBIF and find-or-create the Taxon in one call.
  # @param scientific_name [String]
  # @param group [String, nil] fallback group when GBIF can't classify
  # @return [Result]
  def self.call(scientific_name, group: nil)
    gbif_match = GbifClient.match(scientific_name)
    good = GbifClient.good_match?(gbif_match)
    taxon = find_or_create(scientific_name, gbif_match, good, group)
    Result.new(taxon: taxon, gbif_match: gbif_match, good_match: good)
  end

  # Find-or-create a Taxon given an already-fetched GBIF match.
  def self.find_or_create(scientific_name, gbif_match, is_good_match, user_group = nil)
    canonical = is_good_match && gbif_match ? gbif_match[:canonical_name] : nil
    lookup_name = canonical.presence || scientific_name

    taxon = Taxon.where("LOWER(scientific_name) = LOWER(?)", lookup_name).first

    if taxon
      if is_good_match && gbif_match && taxon.gbif_key.nil?
        attrs = gbif_attributes(gbif_match)
        attrs[:group] = TaxonGroupResolver.resolve(gbif_match) if taxon.group.blank?
        taxon.update(attrs)
      elsif taxon.group.blank? && user_group.present?
        taxon.update(group: user_group)
      end
      taxon
    else
      attrs = { scientific_name: lookup_name }
      if is_good_match && gbif_match
        attrs.merge!(gbif_attributes(gbif_match))
        attrs[:group] = TaxonGroupResolver.resolve(gbif_match)
      elsif user_group.present?
        attrs[:group] = user_group
      else
        attrs[:group] = "other"
      end
      Taxon.create!(attrs)
    end
  end

  # Normalized GBIF attributes for persisting on a Taxon.
  def self.gbif_attributes(match)
    {
      taxon_source: "gbif",
      taxon_id: match[:usage_key]&.to_s,
      gbif_key: match[:usage_key],
      gbif_rank: match[:rank],
      gbif_canonical_name: match[:canonical_name],
      gbif_confidence: match[:confidence],
      gbif_match_type: match[:match_type]
    }
  end
end
