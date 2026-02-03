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

module ::VzekcMap
  PLUGIN_NAME = "vzekc-map"
end

require_relative "lib/vzekc_map/engine"
require_relative "lib/vzekc_map/geo_parser"
require_relative "lib/vzekc_map/member_checker"

after_initialize do
  # Register custom route for member-map page
  Discourse::Application.routes.append do
    get "/member-map" => "users#index", constraints: { format: /(json|html)/ }
  end
end
