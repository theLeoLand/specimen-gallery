# app/services/gbif_client.rb
# Client for GBIF Species API
# Docs: https://www.gbif.org/developer/species

require "net/http"
require "json"
require "openssl"

class GbifClient
  BASE_URL = "https://api.gbif.org/v1/species".freeze
  TIMEOUT = 5 # seconds

  class << self
    # Autocomplete suggestions for a query
    # Returns array of normalized suggestion hashes
    def suggest(query, limit: 10)
      return [] if query.blank? || query.length < 2

      uri = URI("#{BASE_URL}/suggest")
      uri.query = URI.encode_www_form(q: query, limit: limit)

      response = fetch(uri)
      return [] unless response

      response.map do |item|
        {
          key: item["key"],
          scientific_name: item["scientificName"],
          canonical_name: item["canonicalName"],
          rank: item["rank"],
          status: item["status"]
        }
      end
    rescue => e
      Rails.logger.warn("GBIF suggest failed: #{e.message}")
      []
    end

    # Match a scientific name against GBIF backbone taxonomy
    # Returns normalized match hash or nil
    def match(name)
      return nil if name.blank?

      uri = URI("#{BASE_URL}/match")
      uri.query = URI.encode_www_form(name: name, verbose: true)

      response = fetch(uri)
      return nil unless response

      {
        usage_key: response["usageKey"],
        scientific_name: response["scientificName"],
        canonical_name: response["canonicalName"],
        rank: response["rank"],
        confidence: response["confidence"],
        match_type: response["matchType"],
        status: response["status"],
        synonym: response["synonym"],
        kingdom: response["kingdom"],
        phylum: response["phylum"],
        class_name: response["class"],
        order: response["order"],
        family: response["family"],
        genus: response["genus"],
        species: response["species"]
      }
    rescue => e
      Rails.logger.warn("GBIF match failed: #{e.message}")
      nil
    end

    # Check if a match result is "good enough" to trust
    def good_match?(match_result)
      return false unless match_result
      return false unless match_result[:usage_key]
      return false unless match_result[:confidence]

      confidence = match_result[:confidence].to_i
      match_type = match_result[:match_type].to_s.upcase

      confidence >= 80 && %w[EXACT FUZZY].include?(match_type)
    end

    private

    def fetch(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      # SSL configuration - always verify peer certificates
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "SpecimenGallery/1.0"

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        Rails.logger.warn("GBIF API returned #{response.code}: #{response.body}")
        nil
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.warn("GBIF API timeout: #{e.message}")
      nil
    rescue => e
      Rails.logger.warn("GBIF API error: #{e.class} - #{e.message}")
      nil
    end
  end
end
