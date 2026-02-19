module ApplicationHelper
  # Build descriptive alt text for specimen images (SEO + accessibility)
  # Format: "Honey Bee (Apis mellifera) transparent background specimen cutout"
  def specimen_alt_text(specimen, taxon = nil)
    parts = []
    name = specimen.display_name
    scientific = taxon&.scientific_name || specimen.taxon&.scientific_name

    if scientific.present? && scientific != name
      parts << "#{name} (#{scientific})"
    else
      parts << name
    end

    parts << "transparent background specimen cutout"
    parts.join(" — ")
  end
end
