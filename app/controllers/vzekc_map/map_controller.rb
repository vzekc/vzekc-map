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
