# lib/tasks/specimen.rake
#
# Bulk-ingest CC0 specimen photos from iNaturalist:
#   iNat (CC0 photos) -> download -> BiRefNet cutout -> GBIF taxonomy -> store
#
# Runs LOCALLY (needs rembg + real compute). Point it at production by exporting
# the production DATABASE_URL + Tigris (AWS_*) creds, or run against dev first.
#
# Examples:
#   # Preview candidates only (no downloads, no writes):
#   DRY_RUN=1 TAXON="Danaus plexippus" LIMIT=25 bin/rails specimen:ingest
#
#   # Real run into the review queue (default = pending, you QC in admin):
#   TAXON="Danaus plexippus" LIMIT=25 bin/rails specimen:ingest
#
#   # Auto-publish good GBIF matches straight to the gallery:
#   PUBLISH=1 TAXON="Danaus plexippus" LIMIT=25 bin/rails specimen:ingest
#
# Options (ENV):
#   TAXON       (required) scientific name, e.g. "Danaus plexippus"
#   LIMIT       max photos to ingest (default 25)
#   PHOTO_SIZE  iNat size: medium | large | original (default large)
#   PUBLISH     "1" to auto-publish good GBIF matches (default: review queue)
#   DRY_RUN     "1" to only list candidates
#   DOWNLOAD_DELAY seconds between image downloads (default 0.5)

require "net/http"
require "open-uri"
require "tempfile"
require "digest"

namespace :specimen do
  desc "Ingest CC0 specimen photos from iNaturalist (see lib/tasks/specimen.rake)"
  task ingest: :environment do
    taxon_name = ENV["TAXON"].to_s.strip
    abort("TAXON is required, e.g. TAXON=\"Danaus plexippus\"") if taxon_name.blank?

    limit          = (ENV["LIMIT"] || 25).to_i
    photo_size     = (ENV["PHOTO_SIZE"] || "large").strip
    publish        = ENV["PUBLISH"] == "1"
    dry_run        = ENV["DRY_RUN"] == "1"
    download_delay = (ENV["DOWNLOAD_DELAY"] || 0.5).to_f

    log = ->(msg) { puts "[specimen:ingest] #{msg}" }

    log.call("Target: #{taxon_name} | limit: #{limit} | size: #{photo_size} | " \
             "mode: #{dry_run ? 'DRY RUN' : (publish ? 'PUBLISH' : 'REVIEW QUEUE')}")

    unless dry_run || BirefnetBackgroundRemover.available?
      abort("rembg not found. Install with `pipx install \"rembg[cpu,cli]\"` or set REMBG_BIN. " \
            "(Use DRY_RUN=1 to preview candidates without it.)")
    end

    log.call("Fetching CC0 photos from iNaturalist...")
    photos = InaturalistClient.cc0_photos(taxon_name: taxon_name, limit: limit, photo_size: photo_size)
    log.call("Found #{photos.size} CC0 candidate photo(s).")

    if dry_run
      photos.each_with_index do |p, i|
        log.call("#{i + 1}. #{p.scientific_name} (#{p.common_name || 'no common name'}) " \
                 "obs ##{p.observation_id} by #{p.observer_login} — #{p.image_url}")
      end
      log.call("DRY RUN complete — nothing downloaded or saved.")
      next
    end

    stats = Hash.new(0)

    photos.each_with_index do |photo, i|
      prefix = "(#{i + 1}/#{photos.size})"

      if already_imported?(photo.photo_id)
        log.call("#{prefix} skip — already imported iNat photo ##{photo.photo_id}")
        stats[:skipped_existing] += 1
        next
      end

      src = nil
      cutout = nil
      begin
        src = download_image(photo.image_url)
        unless src
          log.call("#{prefix} skip — download failed: #{photo.image_url}")
          stats[:download_failed] += 1
          next
        end

        cutout = BirefnetBackgroundRemover.call(src.path)

        # Automated QC gate: auto-skip clear failures, flag suspicious ones.
        qc = CutoutQualityChecker.call(cutout)
        if qc.reject?
          log.call("#{prefix} qc reject — #{qc.reasons.join(', ')} " \
                   "(opaque=#{qc.opaque_ratio}, blobs=#{qc.subject_blobs})")
          stats[:qc_rejected] += 1
          next
        end

        resolution = TaxonResolver.call(photo.scientific_name)
        taxon = resolution.taxon

        # A QC flag forces review regardless of GBIF match quality.
        needs_review = qc.flag? || !(publish && resolution.good_match?)

        asset = taxon.specimen_assets.build(
          specimen_name: photo.common_name.presence || photo.scientific_name,
          common_name: photo.common_name,
          license: "CC0",
          needs_review: needs_review,
          status: needs_review ? "pending" : "approved",
          bg_removed: true,
          notes: nil, # provenance is admin-only; kept in qc_flags, never public
          qc_flags: provenance_flags(photo, qc)
        )

        asset.image.attach(
          io: File.open(cutout),
          filename: cutout_filename(photo),
          content_type: "image/png"
        )

        if asset.save
          qc_note = qc.flag? ? ", qc:#{qc.reasons.join('/')}" : ""
          log.call("#{prefix} created ##{asset.id} — #{photo.scientific_name} " \
                   "[#{asset.status}#{needs_review ? ', needs_review' : ''}#{qc_note}]")
          stats[qc.flag? ? :created_flagged : :created] += 1
        else
          duplicate = asset.errors[:image].any? { |m| m.include?("already been uploaded") }
          log.call("#{prefix} skip — #{asset.errors.full_messages.join('; ')}")
          stats[duplicate ? :skipped_duplicate : :invalid] += 1
        end
      rescue BirefnetBackgroundRemover::Error => e
        log.call("#{prefix} cutout failed — #{e.message}")
        stats[:cutout_failed] += 1
      rescue => e
        log.call("#{prefix} error — #{e.class}: #{e.message}")
        stats[:error] += 1
      ensure
        src&.close!
        File.delete(cutout) if cutout && File.exist?(cutout)
      end

      sleep(download_delay)
    end

    log.call("Done. #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}")
  end
end

# --- helpers -----------------------------------------------------------------

def already_imported?(photo_id)
  return false if photo_id.blank?
  SpecimenAsset.where("qc_flags ->> 'inat_photo_id' = ?", photo_id.to_s).exists?
end

def download_image(url)
  tmp = Tempfile.new([ "inat", File.extname(URI.parse(url).path).presence || ".jpg" ])
  tmp.binmode
  URI.open(
    url,
    "User-Agent" => InaturalistClient::USER_AGENT,
    read_timeout: 30,
    ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE
  ) do |remote|
    IO.copy_stream(remote, tmp)
  end
  tmp.rewind
  tmp
rescue => e
  Rails.logger.warn("iNat image download failed (#{url}): #{e.message}")
  tmp&.close!
  nil
end

# Provenance + QC metadata. Stored in qc_flags (jsonb) which is NEVER rendered on
# public pages — the source backlink is admin-only, surfaced in the review UI.
def provenance_flags(photo, qc = nil)
  flags = {
    "import_source" => "inaturalist",
    "inat_photo_id" => photo.photo_id.to_s,
    "inat_observation_id" => photo.observation_id.to_s,
    "observer" => photo.observer_login,
    "source_url" => photo.source_url,
    "photo_license" => "cc0",
    "photo_attribution" => photo.attribution,
    "imported_at" => Time.current.iso8601
  }

  if qc
    flags["qc_reasons"]   = qc.reasons if qc.reasons.any?
    flags["opaque_ratio"] = qc.opaque_ratio
    flags["subject_blobs"] = qc.subject_blobs
  end

  flags
end

def cutout_filename(photo)
  base = photo.scientific_name.to_s.parameterize.presence || "specimen"
  "#{base}-inat-#{photo.photo_id}.png"
end
