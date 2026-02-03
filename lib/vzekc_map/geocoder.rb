# frozen_string_literal: true

require "net/http"
require "json"

module VzekcMap
  module Geocoder
    NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse"
    USER_AGENT = "VzekcMap Discourse Plugin"

    # Reverse geocode coordinates to get city and postcode
    #
    # @param lat [Float] Latitude
    # @param lng [Float] Longitude
    # @return [Hash, nil] { city:, postcode: } or nil if geocoding failed
    def self.reverse_geocode(lat, lng)
      uri = URI(NOMINATIM_URL)
      uri.query = URI.encode_www_form(
        lat: lat,
        lon: lng,
        format: "json",
        addressdetails: 1
      )

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept-Language"] = "de,en"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.request(request)
      end

      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      address = data["address"]
      return nil unless address

      # Try different fields for city name
      city = address["city"] || address["town"] || address["village"] || address["municipality"]
      postcode = address["postcode"]

      return nil unless city || postcode

      { city: city, postcode: postcode }
    rescue StandardError => e
      Rails.logger.warn("VzekcMap: Geocoding failed for #{lat},#{lng}: #{e.message}")
      nil
    end

    # Format location name from city and postcode
    #
    # @param city [String, nil] City name
    # @param postcode [String, nil] Postcode
    # @return [String, nil] Formatted name like "10178 Berlin" or just "Berlin" or "10178"
    def self.format_location_name(city, postcode)
      if city && postcode
        "#{postcode} #{city}"
      elsif city
        city
      elsif postcode
        postcode
      end
    end
  end
end
