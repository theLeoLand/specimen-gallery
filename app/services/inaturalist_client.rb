# app/services/inaturalist_client.rb
# Client for the iNaturalist API, used by the bulk ingestion pipeline.
# Docs: https://api.inaturalist.org/v1/docs/
#
# LEGAL: we only ever surface photos whose *photo* license is CC0 (public
# domain). The observation-level license is separate and NOT sufficient, so we
# filter on `photo_license=cc0` AND re-check each photo's `license_code`.
#
# RATE LIMITS (per iNaturalist API recommended practices):
#   - <= 1 request/second (we sleep between pages)
#   - never bulk-scrape; this is for small/medium targeted pulls
#   - media downloads happen elsewhere and must stay < 5GB/hr, < 24GB/day
require "net/http"
require "json"
require "openssl"

class InaturalistClient
  BASE_URL = "https://api.inaturalist.org/v1".freeze
  TIMEOUT = 10 # seconds
  MAX_PER_PAGE = 200
  REQUEST_DELAY = 1.0 # seconds between API requests (respect ~1 req/s)
  USER_AGENT = "SpecimenGallery/1.0 (+https://specimen.gallery; CC0 ingestion)".freeze

  # A single ingest-ready candidate photo.
  Photo = Struct.new(
    :scientific_name, :common_name, :image_url, :photo_id, :photo_license,
    :attribution, :observation_id, :observer_login, :source_url,
    keyword_init: true
  )

  # Fetch CC0-photo candidates for a taxon.
  # @param taxon_name [String] e.g. "Danaus plexippus"
  # @param limit [Integer] max photos to return
  # @param photo_size [String] iNat size token: "medium" | "large" | "original"
  # @return [Array<Photo>]
  def self.cc0_photos(taxon_name:, limit: 25, photo_size: "large")
    new(taxon_name: taxon_name, limit: limit, photo_size: photo_size).cc0_photos
  end

  def initialize(taxon_name:, limit:, photo_size:)
    @taxon_name = taxon_name
    @limit = limit
    @photo_size = photo_size
  end

  def cc0_photos
    collected = []
    page = 1

    while collected.size < @limit
      per_page = [ MAX_PER_PAGE, @limit - collected.size + 20 ].min
      results = fetch_page(page: page, per_page: per_page)
      break if results.blank?

      results.each do |obs|
        photo = extract_representative_photo(obs)
        next unless photo

        collected << photo
        break if collected.size >= @limit
      end

      break if results.size < per_page # no more pages
      page += 1
      sleep(REQUEST_DELAY)
    end

    collected
  end

  private

  def fetch_page(page:, per_page:)
    uri = URI("#{BASE_URL}/observations")
    uri.query = URI.encode_www_form(
      taxon_name: @taxon_name,
      photo_license: "cc0",
      quality_grade: "research",
      photos: true,
      per_page: per_page,
      page: page,
      order_by: "votes",
      order: "desc"
    )

    body = fetch(uri)
    body ? Array(body["results"]) : []
  end

  # Pick ONE representative CC0 photo per observation (the observation's first
  # CC0 photo). An observation often bundles several photos of the same specimen;
  # ingesting all of them would create near-duplicate rows, so we take one per
  # observation to keep the gallery diverse.
  def extract_representative_photo(obs)
    scientific = obs.dig("taxon", "name")
    return nil if scientific.blank?

    photo = Array(obs["photos"]).find { |p| p["license_code"].to_s.downcase == "cc0" }
    return nil unless photo

    url = full_size_url(photo["url"])
    return nil if url.blank?

    Photo.new(
      scientific_name: scientific,
      common_name: obs.dig("taxon", "preferred_common_name"),
      image_url: url,
      photo_id: photo["id"],
      photo_license: "cc0",
      attribution: photo["attribution"],
      observation_id: obs["id"],
      observer_login: obs.dig("user", "login"),
      source_url: "https://www.inaturalist.org/observations/#{obs['id']}"
    )
  end

  # iNat photo URLs come back as the square thumbnail, e.g.
  #   https://inaturalist-open-data.s3.amazonaws.com/photos/123/square.jpg
  # Swap the size token for the requested full size.
  def full_size_url(square_url)
    return nil if square_url.blank?

    square_url.sub(%r{/(square|small|medium|large|thumb)\.}, "/#{@photo_size}.")
  end

  def fetch(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    # Verify peer but skip CRL check (some certs trigger CRL errors in this env,
    # same workaround as GbifClient).
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_callback = ->(_preverify_ok, _store_ctx) { true }

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request["User-Agent"] = USER_AGENT

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      Rails.logger.warn("iNaturalist API returned #{response.code}: #{response.body}")
      nil
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.warn("iNaturalist API timeout: #{e.message}")
    nil
  rescue => e
    Rails.logger.warn("iNaturalist API error: #{e.class} - #{e.message}")
    nil
  end
end
