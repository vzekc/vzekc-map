# frozen_string_literal: true

# name: vzekc-map
# about: Discourse-Plugin zur Anzeige einer Mitgliederkarte mit OpenStreetMap
# meta_topic_id: TODO
# version: 0.0.1
# authors: Hans Hübner
# url: https://github.com/vzekc/vzekc-map
# required_version: 2.7.0

enabled_site_setting :vzekc_map_enabled

register_asset "stylesheets/vzekc-map.scss"

register_svg_icon "map"
register_svg_icon "map-marker-alt"
register_svg_icon "home"
register_svg_icon "house"
register_svg_icon "plus"
register_svg_icon "times"
register_svg_icon "xmark"
register_svg_icon "crosshairs"
register_svg_icon "location-crosshairs"
register_svg_icon "globe"
register_svg_icon "magnifying-glass"
register_svg_icon "user"
register_svg_icon "layer-group"
register_svg_icon "map-pin"
register_svg_icon "external-link-alt"
register_svg_icon "chevron-down"
register_svg_icon "circle-question"

module ::VzekcMap
  PLUGIN_NAME = "vzekc-map"

  def self.notify_map_update
    PluginStore.set("vzekc-map", "last_activity", Time.now.iso8601)

    # Get all member user IDs
    members_group_name = SiteSetting.vzekc_map_members_group_name
    return unless members_group_name.present?

    group = Group.find_by(name: members_group_name)
    return unless group

    member_ids = group.users.pluck(:id)
    return if member_ids.empty?

    # Publish to MessageBus for all members
    MessageBus.publish("/vzekc-map/new-content", { has_new: true }, user_ids: member_ids)
  end
end

require_relative "lib/vzekc_map/engine"
require_relative "lib/vzekc_map/geo_parser"
require_relative "lib/vzekc_map/geocoder"
require_relative "lib/vzekc_map/member_checker"
require_relative "lib/vzekc_map/woltlab_sync"

after_initialize do
  # Register custom route for member-map page
  Discourse::Application.routes.append do
    get "/member-map" => "users#index", constraints: { format: /(json|html)/ }
  end

  # Register topic custom field for POI coordinates
  register_topic_custom_field_type("vzekc_map_coordinates", :string)

  # Register user custom field for last map visit timestamp
  register_user_custom_field_type("vzekc_map_last_visit", :string)

  # Update global timestamp when user location changes
  on(:user_custom_field_changed) do |user, field_name|
    if field_name == "Geoinformation"
      VzekcMap.notify_map_update
    end
  end

  # Update global timestamp when POI topic is created
  on(:topic_created) do |topic, opts, user|
    poi_category_id = SiteSetting.vzekc_map_poi_category_id
    if poi_category_id.present? && topic.category_id == poi_category_id.to_i
      VzekcMap.notify_map_update
    end
  end

  # Update global timestamp when POI topic is edited
  on(:post_edited) do |post, topic_changed|
    topic = post.topic
    poi_category_id = SiteSetting.vzekc_map_poi_category_id
    if poi_category_id.present? && topic&.category_id == poi_category_id.to_i
      VzekcMap.notify_map_update
    end
  end

  # Serialize to topic JSON
  add_to_serializer(:topic_view, :vzekc_map_coordinates) do
    object.topic.custom_fields["vzekc_map_coordinates"]
  end

  # Expose geo locations in user serializer for profile page
  add_to_serializer(:user, :vzekc_map_locations) do
    return nil unless SiteSetting.vzekc_map_enabled
    geo_string = object.custom_fields["Geoinformation"]
    return nil if geo_string.blank?
    VzekcMap::GeoParser.parse(geo_string)
  end

  # After first post is created, extract coordinates from post body and save as topic custom field
  on(:post_created) do |post, opts, user|
    # Only process first posts (topic creation)
    next unless post.is_first_post?

    topic = post.topic
    next unless topic

    poi_category_id = SiteSetting.vzekc_map_poi_category_id
    next unless poi_category_id.present? && topic.category_id == poi_category_id.to_i

    raw = post.raw || ""

    # Match map link format: /member-map?poi=lat,lng,zoom
    if raw =~ /\/member-map\?poi=(-?\d+\.?\d*),(-?\d+\.?\d*),(\d+)/
      lat = $1.to_f
      lng = $2.to_f
      zoom = $3.to_i

      if VzekcMap::GeoParser.send(:valid_coordinates?, lat, lng)
        geo_uri = VzekcMap::GeoParser.build_geo_uri(lat, lng, zoom: zoom)
        topic.custom_fields["vzekc_map_coordinates"] = geo_uri
        topic.save_custom_fields
      end
    end
  end
end
