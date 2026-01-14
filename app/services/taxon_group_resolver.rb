# app/services/taxon_group_resolver.rb
# Resolves specimen group from GBIF classification data
#
# Groups:
#   plant, fungi, insect, arachnid, mammal, bird, fish,
#   reptile_amphibian, marine_invertebrate, microbe, mineral, other

class TaxonGroupResolver
  # All valid group values
  GROUPS = %w[
    plant
    fungi
    insect
    arachnid
    mammal
    bird
    fish
    reptile_amphibian
    marine_invertebrate
    microbe
    mineral
    other
  ].freeze

  # Display names and icons for each group
  GROUP_METADATA = {
    "plant" => { name: "Plants", icon: "🌿" },
    "fungi" => { name: "Fungi", icon: "🍄" },
    "insect" => { name: "Insects", icon: "🐝" },
    "arachnid" => { name: "Arachnids", icon: "🕷️" },
    "mammal" => { name: "Mammals", icon: "🐾" },
    "bird" => { name: "Birds", icon: "🐦" },
    "fish" => { name: "Fish", icon: "🐟" },
    "reptile_amphibian" => { name: "Reptiles & Amphibians", icon: "🦎" },
    "marine_invertebrate" => { name: "Marine Invertebrates", icon: "🐙" },
    "microbe" => { name: "Microbes", icon: "🦠" },
    "mineral" => { name: "Minerals & Rocks", icon: "🪨" },
    "other" => { name: "Other", icon: "✳️" }
  }.freeze

  # Marine invertebrate phyla
  MARINE_INVERTEBRATE_PHYLA = %w[
    Mollusca
    Cnidaria
    Echinodermata
    Porifera
    Annelida
    Bryozoa
    Brachiopoda
  ].freeze

  class << self
    # Resolve group from GBIF match data
    # @param gbif_match [Hash] The normalized GBIF match response
    # @return [String] The resolved group (defaults to "other")
    def resolve(gbif_match)
      return "other" if gbif_match.blank?

      kingdom = gbif_match[:kingdom].to_s.strip
      phylum = gbif_match[:phylum].to_s.strip
      class_name = gbif_match[:class_name].to_s.strip
      order = gbif_match[:order].to_s.strip

      resolve_from_classification(kingdom, phylum, class_name, order)
    end

    # Resolve from raw classification strings
    def resolve_from_classification(kingdom, phylum = nil, class_name = nil, order = nil)
      case kingdom
      when "Plantae"
        "plant"
      when "Fungi"
        "fungi"
      when "Bacteria", "Archaea"
        "microbe"
      when "Protozoa", "Chromista"
        # Protists and chromists are typically microbial
        "microbe"
      when "Animalia"
        resolve_animal(phylum, class_name, order)
      when "Viruses"
        "microbe"
      else
        "other"
      end
    end

    # Get display name for a group
    def display_name(group)
      GROUP_METADATA.dig(group, :name) || group&.titleize || "Unknown"
    end

    # Get icon for a group
    def icon(group)
      GROUP_METADATA.dig(group, :icon) || "✳️"
    end

    # Get all groups with metadata for UI
    def all_with_metadata
      GROUPS.map do |group|
        {
          value: group,
          name: display_name(group),
          icon: icon(group)
        }
      end
    end

    private

    def resolve_animal(phylum, class_name, order)
      # Check class first for vertebrates
      case class_name
      when "Mammalia"
        "mammal"
      when "Aves"
        "bird"
      when "Actinopterygii", "Chondrichthyes", "Agnatha", "Sarcopterygii"
        # Bony fish, cartilaginous fish (sharks/rays), jawless fish, lobe-finned fish
        "fish"
      when "Reptilia"
        "reptile_amphibian"
      when "Amphibia"
        "reptile_amphibian"
      when "Insecta"
        "insect"
      when "Arachnida"
        "arachnid"
      when "Malacostraca", "Maxillopoda", "Branchiopoda"
        # Crustaceans (crabs, lobsters, shrimp, barnacles)
        "marine_invertebrate"
      when "Cephalopoda", "Gastropoda", "Bivalvia"
        # Molluscs (octopus, snails, clams)
        "marine_invertebrate"
      when "Anthozoa", "Scyphozoa", "Hydrozoa"
        # Cnidarians (corals, jellyfish)
        "marine_invertebrate"
      when "Asteroidea", "Echinoidea", "Holothuroidea"
        # Echinoderms (starfish, sea urchins, sea cucumbers)
        "marine_invertebrate"
      else
        # Fall back to phylum-based classification
        resolve_animal_by_phylum(phylum, class_name)
      end
    end

    def resolve_animal_by_phylum(phylum, class_name)
      # Check for marine invertebrate phyla
      if MARINE_INVERTEBRATE_PHYLA.include?(phylum)
        return "marine_invertebrate"
      end

      # Arthropods need special handling
      if phylum == "Arthropoda"
        # If we got here, class wasn't Insecta or Arachnida
        # Could be crustacean, myriapod, etc.
        case class_name
        when "Chilopoda", "Diplopoda"
          # Centipedes and millipedes - treat as other (terrestrial)
          "other"
        else
          # Default arthropods to insect (most common case)
          "insect"
        end
      elsif phylum == "Chordata"
        # Vertebrate we couldn't classify by class
        "other"
      else
        # Unknown phylum
        "other"
      end
    end
  end
end

