# frozen_string_literal: true

module VzekcMap
  class MapController < ::ApplicationController
    requires_plugin VzekcMap::PLUGIN_NAME
    requires_login

    before_action :ensure_member

    # GET /vzekc-map/locations.json
    #
    # Returns a list of all member locations for displaying on the map
    #
    # @return [JSON] {
    #   locations: [
    #     {
    #       user: { id, username, name, avatar_template },
    #       coordinates: [{ lat, lng, zoom }]
    #     }
    #   ]
    # }
    def locations
      # Query users with Geoinformation custom field
      user_fields = UserCustomField.where(name: "Geoinformation")
                                   .where.not(value: [nil, ""])
                                   .includes(:user)

      locations = []

      user_fields.each do |ucf|
        user = ucf.user
        next unless user

        # Parse the geoinformation
        coordinates = GeoParser.parse(ucf.value)
        next if coordinates.empty?

        locations << {
          user: {
            id: user.id,
            username: user.username,
            name: user.name,
            avatar_template: user.avatar_template
          },
          coordinates: coordinates
        }
      end

      render json: { locations: locations }
    end

    # POST /vzekc-map/locations.json
    #
    # Add a new location for the current user
    #
    # @param lat [Float] Latitude
    # @param lng [Float] Longitude
    # @param zoom [Integer] Optional zoom level
    def add_location
      lat = params[:lat].to_f
      lng = params[:lng].to_f
      zoom = params[:zoom]&.to_i

      # Validate coordinates
      unless GeoParser.send(:valid_coordinates?, lat, lng)
        return render json: { error: I18n.t("vzekc_map.errors.invalid_coordinates") }, status: 422
      end

      # Reverse geocode to get location name
      location_name = nil
      geocode_result = VzekcMap::Geocoder.reverse_geocode(lat, lng)
      if geocode_result
        location_name = VzekcMap::Geocoder.format_location_name(geocode_result[:city], geocode_result[:postcode])
      end

      # Build new geo string with name
      new_geo = GeoParser.build_geo_uri(lat, lng, zoom: zoom, name: location_name)

      # Get current geoinformation
      current_value = current_user.custom_fields["Geoinformation"] || ""

      # Append new location
      new_value = current_value.blank? ? new_geo : "#{current_value} #{new_geo}"

      # Save
      current_user.custom_fields["Geoinformation"] = new_value
      current_user.save_custom_fields

      # Return updated coordinates
      coordinates = GeoParser.parse(new_value)
      render json: { coordinates: coordinates }
    end

    # DELETE /vzekc-map/locations/:index.json
    #
    # Delete a location for the current user by index
    #
    # @param index [Integer] The index of the location to delete (0-based)
    def delete_location
      index = params[:index].to_i

      # Get current geoinformation
      current_value = current_user.custom_fields["Geoinformation"] || ""
      coordinates = GeoParser.parse(current_value)

      # Validate index
      if index < 0 || index >= coordinates.length
        return render json: { error: I18n.t("vzekc_map.errors.invalid_location_index") }, status: 422
      end

      # Remove the location at index by rebuilding the geo string
      # We need to work with the raw parts, not parsed coordinates
      parts = current_value.strip.split(/\s+/)
      valid_parts = parts.select { |part| GeoParser.parse(part).any? }

      if index < valid_parts.length
        valid_parts.delete_at(index)
      end

      # Save updated value
      new_value = valid_parts.join(" ")
      current_user.custom_fields["Geoinformation"] = new_value
      current_user.save_custom_fields

      # Return updated coordinates
      coordinates = GeoParser.parse(new_value)
      render json: { coordinates: coordinates }
    end

    # GET /vzekc-map/pois.json
    #
    # Returns all POI topics from the configured category with coordinates
    #
    # @return [JSON] {
    #   pois: [
    #     {
    #       topic_id, title, slug,
    #       coordinates: { lat, lng, zoom, name },
    #       user: { id, username, avatar_template }
    #     }
    #   ]
    # }
    def pois
      return render json: { pois: [] } unless SiteSetting.vzekc_map_poi_enabled

      category_id = SiteSetting.vzekc_map_poi_category_id
      return render json: { pois: [] } if category_id.blank?

      topics = Topic.where(category_id: category_id)
                    .where(deleted_at: nil)
                    .includes(:user)

      pois = topics.filter_map do |topic|
        coords_str = topic.custom_fields["vzekc_map_coordinates"]
        next unless coords_str.present?

        coords = GeoParser.parse(coords_str).first
        next unless coords

        {
          topic_id: topic.id,
          title: topic.title,
          slug: topic.slug,
          coordinates: coords,
          user: {
            id: topic.user.id,
            username: topic.user.username,
            avatar_template: topic.user.avatar_template
          }
        }
      end

      render json: { pois: pois }
    end

    private

    # Ensure current user is a member of the configured group
    def ensure_member
      unless MemberChecker.active_member?(current_user)
        raise Discourse::InvalidAccess.new(
          I18n.t("vzekc_map.errors.members_only"),
          nil,
          custom_message: "vzekc_map.errors.members_only"
        )
      end
    end
  end
end
