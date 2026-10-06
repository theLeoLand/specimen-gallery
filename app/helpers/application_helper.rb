module ApplicationHelper
  CC0_LICENSE_URL = "https://creativecommons.org/publicdomain/zero/1.0/".freeze
  CC_BY_LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/".freeze

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

  # Grid/thumbnail src. In production this is a direct Tigris URL so the browser
  # does not send one Rails request per image (that saturates the small Fly
  # machine and some cards render as alt text). Disk storage keeps the local route.
  def specimen_image_src(specimen)
    return unless specimen&.image&.attached?

    blob = specimen.image.blob
    if blob.service.class.name.demodulize == "S3Service"
      blob.url(expires_in: 12.hours, disposition: :inline)
    else
      url_for(specimen.image)
    end
  end

  # SEO-friendly, stable, ABSOLUTE URL for a specimen's image on our own domain.
  # Uses rails_blob_url (not Active Storage's url_for, which returns a relative
  # path and breaks og:image/structured-data crawling). The signed_id route is
  # permanent (does not expire), so Google can index it reliably.
  def specimen_image_url_abs(specimen)
    return nil unless specimen.image.attached?

    rails_blob_url(specimen.image)
  end

  # A human/SEO-friendly download filename, e.g. "monarch-butterfly-danaus-plexippus-cc0.png"
  def specimen_download_filename(specimen)
    specimen.download_filename
  end

  # Canonical license URL for schema.org `license` / `acquireLicensePage`.
  def specimen_license_url(specimen)
    specimen.license == "CC0" ? CC0_LICENSE_URL : CC_BY_LICENSE_URL
  end

  # schema.org ImageObject for a single specimen. The `license` +
  # `acquireLicensePage` pair is what powers Google Images' usage-rights
  # ("free to use") filter — the key channel for a CC0 cutout library.
  def specimen_image_jsonld(specimen)
    img = specimen_image_url_abs(specimen)
    scientific = specimen.taxon&.scientific_name

    data = {
      "@context" => "https://schema.org",
      "@type" => "ImageObject",
      "name" => specimen_alt_text(specimen),
      "description" => "Free #{specimen.license == 'CC0' ? 'public domain (CC0)' : 'CC-BY'} transparent-background cutout of #{specimen.display_name}.",
      "contentUrl" => img,
      "thumbnailUrl" => img,
      "url" => specimen_asset_url(specimen),
      "encodingFormat" => "image/png",
      "datePublished" => specimen.created_at&.iso8601,
      "dateModified" => specimen.updated_at&.iso8601,
      "license" => specimen_license_url(specimen),
      "acquireLicensePage" => specimen_asset_url(specimen),
      "copyrightNotice" => specimen.license == "CC0" ? "CC0 1.0 Universal (Public Domain Dedication)" : "CC BY 4.0",
      "creditText" => specimen.attribution_name.presence,
      "isAccessibleForFree" => true
    }

    if scientific.present?
      about = { "@type" => "Taxon", "name" => scientific }
      about["alternateName"] = specimen.common_name if specimen.common_name.present?
      data["about"] = about
    end

    if specimen.attribution_name.present?
      creator = { "@type" => "Person", "name" => specimen.attribution_name }
      creator["url"] = specimen.attribution_url if specimen.attribution_url.present?
      data["creator"] = creator
    end

    data.compact
  end

  # schema.org CollectionPage + ItemList for a taxon's set of specimens.
  def taxon_collection_jsonld(taxon, specimens)
    {
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "name" => "#{taxon.scientific_name} — CC0 transparent PNG cutouts",
      "url" => taxon_url(taxon),
      "about" => { "@type" => "Taxon", "name" => taxon.scientific_name },
      "mainEntity" => {
        "@type" => "ItemList",
        "numberOfItems" => specimens.size,
        "itemListElement" => specimens.each_with_index.map do |specimen, i|
          { "@type" => "ListItem", "position" => i + 1, "url" => specimen_asset_url(specimen) }
        end
      }
    }
  end

  # Render a JSON-LD <script> block safely. Neutralizes <, >, & so user-supplied
  # text (e.g. a specimen name containing "</script>") can never break out.
  def json_ld_tag(data)
    json = data.to_json.gsub("<", '\u003c').gsub(">", '\u003e').gsub("&", '\u0026')
    content_tag(:script, json.html_safe, type: "application/ld+json")
  end

  # Preserve browse filters when paging. Compact so blank filters don't pollute URLs.
  def browse_query_params(overrides = {})
    {
      q: params[:q].presence,
      group: params[:group].presence,
      id_status: params[:id_status].presence,
      sex: params[:sex].presence,
      life_stage: params[:life_stage].presence,
      view: params[:view].presence,
      part: params[:part].presence
    }.merge(overrides).compact
  end

  # Page numbers with ellipsis gaps, e.g. [1, :gap, 4, 5, 6, :gap, 12]
  def pagination_pages(current, total, window: 2)
    return [] if total <= 1

    keep = [ 1, total ]
    ((current - window)..(current + window)).each { |p| keep << p if p.between?(1, total) }
    keep.uniq.sort.each_with_object([]) do |p, acc|
      acc << :gap if acc.last.is_a?(Integer) && p > acc.last + 1
      acc << p
    end
  end
end
