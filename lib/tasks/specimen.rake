# lib/tasks/specimen.rake
#
# Bulk-ingest CC0 specimen photos from iNaturalist:
#   iNat (CC0 photos) -> download -> BiRefNet cutout -> QC -> GBIF taxonomy -> store
#
# Runs LOCALLY (needs rembg + real compute). Point it at production by exporting
# the production DATABASE_URL + Tigris (AWS_*) creds (see bin/ingest --prod).
#
# Two tasks:
#   specimen:ingest        one taxon (TAXON=..., LIMIT=...)
#   specimen:ingest_batch  a rotating set from config/ingest_species.txt
#
# Single-taxon examples:
#   DRY_RUN=1 TAXON="Danaus plexippus" LIMIT=25 bin/rails specimen:ingest
#   TAXON="Danaus plexippus" LIMIT=25 bin/rails specimen:ingest
#   PUBLISH=1 TAXON="Danaus plexippus" LIMIT=25 bin/rails specimen:ingest
#
# Batch examples (picks the fewest-imported species first, so coverage spreads):
#   DRY_RUN=1 bin/rails specimen:ingest_batch
#   bin/rails specimen:ingest_batch                     # 5 species x 5 each
#   PER_SPECIES=10 SPECIES_PER_RUN=8 bin/rails specimen:ingest_batch
#
# Options (ENV):
#   TAXON           (ingest only) scientific name, e.g. "Danaus plexippus"
#   LIMIT           (ingest only) max photos to ingest (default 25)
#   SPECIES_FILE    (batch) path to the species list (default config/ingest_species.txt)
#   PER_SPECIES     (batch) photos per species this run (default 5)
#   SPECIES_PER_RUN (batch) how many species to process this run (default 5)
#   PHOTO_SIZE      iNat size: medium | large | original (default large)
#   PUBLISH         "1" to auto-publish good GBIF matches (default: review queue)
#   DRY_RUN         "1" to only list candidates
#   DOWNLOAD_DELAY  seconds between image downloads (default 0.5)

require "net/http"
require "open-uri"
require "tempfile"
require "digest"

namespace :specimen do
  desc "Ingest CC0 specimen photos from iNaturalist for ONE taxon"
  task ingest: :environment do
    taxon_name = ENV["TAXON"].to_s.strip
    abort("TAXON is required, e.g. TAXON=\"Danaus plexippus\"") if taxon_name.blank?

    opts = ingest_opts
    log = ->(msg) { puts "[specimen:ingest] #{msg}" }
    log.call("Mode: #{ingest_mode(opts)} | limit: #{opts[:limit]} | size: #{opts[:photo_size]}")

    ensure_rembg!(opts[:dry_run])

    stats = Hash.new(0)
    ingest_taxon(taxon_name, log: log, stats: stats, **opts)
    log.call("Done. #{format_stats(stats)}")
  end

  desc "Batch-ingest a rotating set of species from config/ingest_species.txt"
  task ingest_batch: :environment do
    species_file    = ENV["SPECIES_FILE"].presence || Rails.root.join("config/ingest_species.txt").to_s
    per_species     = (ENV["PER_SPECIES"] || 5).to_i
    species_per_run = (ENV["SPECIES_PER_RUN"] || 5).to_i

    opts = ingest_opts(default_limit: per_species)
    opts[:limit] = per_species # per-species cap for a batch run

    log = ->(msg) { puts "[specimen:ingest_batch] #{msg}" }

    all_species = read_species_file(species_file)
    abort("No species found in #{species_file}") if all_species.empty?

    selected = select_species(all_species, species_per_run)
    log.call("Species file: #{species_file} (#{all_species.size} listed)")
    log.call("This run: #{selected.size} species x #{per_species} each " \
             "(up to #{selected.size * per_species} specimens) | mode: #{ingest_mode(opts)}")
    log.call("Selected: #{selected.join(', ')}")

    ensure_rembg!(opts[:dry_run])

    stats = Hash.new(0)
    selected.each_with_index do |name, i|
      log.call("=== [#{i + 1}/#{selected.size}] #{name} ===")
      ingest_taxon(name, log: log, stats: stats, **opts)
    end

    log.call("Batch done. #{format_stats(stats)}")
  end
end

# --- core ingestion ----------------------------------------------------------

# Ingest up to `limit` CC0 photos for a single taxon, mutating `stats`.
def ingest_taxon(taxon_name, limit:, photo_size:, publish:, dry_run:, download_delay:, log:, stats:)
  taxon_name = taxon_name.to_s.strip
  return if taxon_name.blank?

  photos = InaturalistClient.cc0_photos(taxon_name: taxon_name, limit: limit, photo_size: photo_size)
  log.call("#{taxon_name}: found #{photos.size} CC0 candidate photo(s).")

  if dry_run
    photos.each_with_index do |p, i|
      log.call("  #{i + 1}. #{p.scientific_name} (#{p.common_name || 'no common name'}) " \
               "obs ##{p.observation_id} by #{p.observer_login}")
    end
    stats[:dry_listed] += photos.size
    return
  end

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
end

# --- option/helper plumbing --------------------------------------------------

def ingest_opts(default_limit: 25)
  {
    limit: (ENV["LIMIT"] || default_limit).to_i,
    photo_size: (ENV["PHOTO_SIZE"] || "large").strip,
    publish: ENV["PUBLISH"] == "1",
    dry_run: ENV["DRY_RUN"] == "1",
    download_delay: (ENV["DOWNLOAD_DELAY"] || 0.5).to_f
  }
end

def ingest_mode(opts)
  opts[:dry_run] ? "DRY RUN" : (opts[:publish] ? "PUBLISH" : "REVIEW QUEUE")
end

def ensure_rembg!(dry_run)
  return if dry_run || BirefnetBackgroundRemover.available?

  abort("rembg not found. Install with `pipx install \"rembg[cpu,cli]\"` or set REMBG_BIN. " \
        "(Use DRY_RUN=1 to preview candidates without it.)")
end

def format_stats(stats)
  return "nothing to do" if stats.empty?
  stats.map { |k, v| "#{k}=#{v}" }.join(" ")
end

# Read a species list file: one scientific name per line; # comments and blanks ignored.
def read_species_file(path)
  return [] unless File.exist?(path)

  File.readlines(path, chomp: true).filter_map do |line|
    name = line.strip
    next if name.empty? || name.start_with?("#")

    name
  end.uniq
end

# Pick `count` species, prioritizing those with the FEWEST imported specimens so
# far (ties broken randomly) so coverage spreads across the list over time.
def select_species(species, count)
  counts = imported_counts_by_name(species)
  species.sort_by { |name| [ counts[name.downcase] || 0, rand ] }.first(count)
end

# Map lowercased scientific name -> count of imported specimens under that taxon.
def imported_counts_by_name(names)
  return {} if names.empty?

  SpecimenAsset
    .joins(:taxon)
    .where("specimen_assets.qc_flags ->> 'import_source' IS NOT NULL")
    .where("LOWER(taxa.scientific_name) IN (?)", names.map(&:downcase))
    .group("LOWER(taxa.scientific_name)")
    .count
end

# --- shared helpers ----------------------------------------------------------

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
