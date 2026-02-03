# frozen_string_literal: true

module VzekcMap
  module GeoParser
    # Parse geoinformation string into array of coordinate hashes
    # Supports multiple formats:
    # - geo:lat,lng?z=zoom&name=Name (with location name): geo:52.535150,13.394236?z=19&name=Berlin%20(10178)
    # - geo:lat,lng?z=zoom (most common): geo:52.535150,13.394236?z=19
    # - geo:lat,lng (no zoom): geo:50.800411,6.914046
    # - geo: lat,lng (space after colon): geo: 49.536401,8.350006
    # - Raw lat,lng: 50.554224,9.676251
    # - Multiple locations (space-separated): geo:48.886...9.126... geo:48.774...9.239...
    # - OpenStreetMap URL: https://www.openstreetmap.org/?#map=19/52.129158/11.604304
    # - Typos like eo: instead of geo:
    #
    # @param geo_string [String] The geoinformation string to parse
    # @return [Array<Hash>] Array of { lat:, lng:, zoom:, name: } hashes
    def self.parse(geo_string)
      return [] if geo_string.blank?

      locations = []

      # Split by whitespace to handle multiple locations
      parts = geo_string.strip.split(/\s+/)

      parts.each do |part|
        location = parse_single(part)
        locations << location if location
      end

      locations
    end

    private

    # Parse a single location string
    #
    # @param str [String] A single location string
    # @return [Hash, nil] { lat:, lng:, zoom: } or nil if parsing failed
    def self.parse_single(str)
      return nil if str.blank?

      # Try OpenStreetMap URL format: https://www.openstreetmap.org/?#map=19/52.129158/11.604304
      if str.include?("openstreetmap.org")
        return parse_osm_url(str)
      end

      # Try geo: format (including typos like eo:)
      # Matches: geo:lat,lng?z=zoom, geo: lat,lng, eo:lat,lng, etc.
      if str =~ /^[eg]?eo:\s*/i
        return parse_geo_uri(str)
      end

      # Try raw lat,lng format
      if str =~ /^-?\d+\.?\d*,\s*-?\d+\.?\d*$/
        return parse_raw_coords(str)
      end

      nil
    end

    # Parse OpenStreetMap URL
    # Format: https://www.openstreetmap.org/?#map=zoom/lat/lng
    #
    # @param url [String] OpenStreetMap URL
    # @return [Hash, nil] { lat:, lng:, zoom:, name: } or nil
    def self.parse_osm_url(url)
      # Extract map parameter: #map=zoom/lat/lng
      if url =~ /[#?&]map=(\d+)\/(-?\d+\.?\d*)\/(-?\d+\.?\d*)/
        zoom = $1.to_i
        lat = $2.to_f
        lng = $3.to_f

        return nil unless valid_coordinates?(lat, lng)

        { lat: lat, lng: lng, zoom: zoom, name: nil }
      else
        nil
      end
    end

    # Parse geo: URI format
    # Formats:
    # - geo:lat,lng?z=zoom&name=Name
    # - geo:lat,lng?z=zoom
    # - geo:lat,lng
    # - geo: lat,lng (with space)
    # - eo:lat,lng (typo)
    #
    # @param uri [String] geo: URI string
    # @return [Hash, nil] { lat:, lng:, zoom:, name: } or nil
    def self.parse_geo_uri(uri)
      # Remove geo:/eo: prefix and optional space
      coords_part = uri.sub(/^[eg]?eo:\s*/i, "")

      # Extract zoom from ?z= parameter if present
      zoom = nil
      if coords_part =~ /[?&]z=(\d+)/
        zoom = $1.to_i
      end

      # Extract name from ?name= parameter if present
      name = nil
      if coords_part =~ /[?&]name=([^&]+)/
        name = URI.decode_www_form_component($1)
      end

      # Remove query string to get just coordinates
      coords_part = coords_part.split("?").first

      # Parse lat,lng
      if coords_part =~ /^(-?\d+\.?\d*),\s*(-?\d+\.?\d*)$/
        lat = $1.to_f
        lng = $2.to_f

        return nil unless valid_coordinates?(lat, lng)

        { lat: lat, lng: lng, zoom: zoom, name: name }
      else
        nil
      end
    end

    # Parse raw lat,lng format
    #
    # @param str [String] Raw coordinates string "lat,lng"
    # @return [Hash, nil] { lat:, lng:, zoom:, name: } or nil
    def self.parse_raw_coords(str)
      if str =~ /^(-?\d+\.?\d*),\s*(-?\d+\.?\d*)$/
        lat = $1.to_f
        lng = $2.to_f

        return nil unless valid_coordinates?(lat, lng)

        { lat: lat, lng: lng, zoom: nil, name: nil }
      else
        nil
      end
    end

    # Validate latitude and longitude values
    #
    # @param lat [Float] Latitude
    # @param lng [Float] Longitude
    # @return [Boolean] true if valid
    def self.valid_coordinates?(lat, lng)
      lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
    end

    # Build a geo: URI string from coordinates
    #
    # @param lat [Float] Latitude
    # @param lng [Float] Longitude
    # @param zoom [Integer, nil] Optional zoom level
    # @param name [String, nil] Optional location name
    # @return [String] geo: URI string
    def self.build_geo_uri(lat, lng, zoom: nil, name: nil)
      uri = "geo:#{lat},#{lng}"
      params = []
      params << "z=#{zoom}" if zoom
      params << "name=#{URI.encode_www_form_component(name)}" if name.present?
      uri += "?#{params.join('&')}" if params.any?
      uri
    end
  end
end
