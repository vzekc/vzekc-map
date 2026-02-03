# vzekc-map - Member Location Map Plugin

## Overview

A Discourse plugin that displays a map of member locations using OpenStreetMap/Leaflet. Only accessible to Vereinsmitglieder. Designed for future extensibility with other POIs.

## Data Source

**Geoinformation custom field** - stored in `user_custom_fields` with name `Geoinformation`

Formats to parse:
- `geo:lat,lng?z=zoom` (most common): `geo:52.535150,13.394236?z=19`
- `geo:lat,lng` (no zoom): `geo:50.800411,6.914046`
- `geo: lat,lng` (space after colon): `geo: 49.536401,8.350006`
- Raw `lat,lng`: `50.554224,9.676251`
- Multiple locations (space-separated): `geo:48.886...9.126... geo:48.774...9.239...`
- OpenStreetMap URL: `https://www.openstreetmap.org/?#map=19/52.129158/11.604304`
- Typos like `eo:` instead of `geo:`

## Plugin Structure

```
vzekc-map/
├── plugin.rb                           # Main plugin file
├── lib/
│   └── vzekc_map/
│       ├── engine.rb                   # Rails engine
│       └── geo_parser.rb               # Geoinformation parsing logic
├── config/
│   ├── routes.rb                       # API routes
│   ├── settings.yml                    # Plugin settings
│   └── locales/
│       ├── client.de.yml
│       ├── client.en.yml
│       ├── server.de.yml
│       └── server.en.yml
├── app/
│   └── controllers/
│       └── vzekc_map/
│           └── map_controller.rb       # API endpoint for map data
└── assets/
    ├── stylesheets/
    │   └── vzekc-map.scss
    └── javascripts/
        └── discourse/
            ├── vzekc-map-route-map.js  # Route mapping
            ├── routes/
            │   └── member-map.js       # Ember route
            ├── templates/
            │   └── member-map.gjs      # Map page template
            └── components/
                └── member-map.gjs      # Map component with Leaflet
```

## Implementation Steps

### 1. Backend - plugin.rb
- Define plugin metadata (name: vzekc-map)
- Enable site setting `vzekc_map_enabled`
- Register route `/member-map`
- Define module `::VzekcMap`
- Require engine

### 2. Backend - Engine & Routes
**lib/vzekc_map/engine.rb:**
```ruby
module ::VzekcMap
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace VzekcMap
  end
end
```

**config/routes.rb:**
```ruby
VzekcMap::Engine.routes.draw do
  get "/locations" => "map#locations"
end

Discourse::Application.routes.draw do
  mount ::VzekcMap::Engine, at: "vzekc-map"
end
```

### 3. Backend - GeoParser
**lib/vzekc_map/geo_parser.rb:**
- Parse all coordinate formats into `[{lat:, lng:, zoom:}]` arrays
- Handle multiple locations per user
- Normalize typos and edge cases

### 4. Backend - MapController
**app/controllers/vzekc_map/map_controller.rb:**
- `GET /vzekc-map/locations.json`
- Require login + vereinsmitglieder membership
- Query users with Geoinformation custom field
- Parse coordinates using GeoParser
- Return JSON: `{ locations: [{ user: {...}, coordinates: [{lat, lng}] }] }`

### 5. Frontend - Route Map
**assets/javascripts/discourse/vzekc-map-route-map.js:**
```javascript
export default function () {
  this.route("memberMap", { path: "/member-map" });
}
```

### 6. Frontend - Route
**assets/javascripts/discourse/routes/member-map.js:**
- Fetch `/vzekc-map/locations.json`
- Pass data to template

### 7. Frontend - Map Component
**assets/javascripts/discourse/components/member-map.gjs:**
- Load Leaflet.js from CDN or bundle
- Initialize OpenStreetMap tile layer
- Add markers for each user location
- Popup with username and avatar on click
- Cluster markers when zoomed out (using Leaflet.markercluster)

### 8. Settings
**config/settings.yml:**
```yaml
vzekc_map:
  vzekc_map_enabled:
    default: false
    client: true
  vzekc_map_members_group_name:
    default: 'vereinsmitglieder'
    type: string
    client: false
  vzekc_map_default_center_lat:
    default: 51.1657
    type: float
    client: true
  vzekc_map_default_center_lng:
    default: 10.4515
    type: float
    client: true
  vzekc_map_default_zoom:
    default: 6
    type: integer
    client: true
```

### 9. Locales
German and English translations for:
- Page title: "Mitgliederkarte" / "Member Map"
- Error messages
- UI labels

## Access Control

- Route requires login (`requires_login`)
- API checks membership in `vzekc_map_members_group_name` group
- Same pattern as vzekc-verlosung plugin's `MemberChecker`

## Leaflet Integration

Options:
1. **CDN** - Load from unpkg/cdnjs in component (simplest)
2. **Vendor bundle** - Copy to `assets/vendor/` (offline support)

Recommended: CDN for initial implementation, can bundle later if needed.

```javascript
// In component, dynamically load Leaflet
const loadLeaflet = async () => {
  if (window.L) return window.L;
  // Load CSS
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
  document.head.appendChild(link);
  // Load JS
  await import('https://unpkg.com/leaflet@1.9.4/dist/leaflet.js');
  return window.L;
};
```

## Future Extensibility

The architecture supports adding other POI types:
- Separate API endpoints for different POI categories
- Map component accepts `layers` prop for toggling visibility
- Settings for enabling/disabling POI types

## Verification

1. Run plugin in development: `LOAD_PLUGINS=1 bin/rails s`
2. Navigate to `/member-map` as logged-in vereinsmitglied
3. Verify map displays with markers for users with Geoinformation
4. Click marker to see user popup
5. Test as non-member - should be denied access
6. Test as logged-out user - should redirect to login

## Files to Create

1. `plugin.rb`
2. `lib/vzekc_map/engine.rb`
3. `lib/vzekc_map/geo_parser.rb`
4. `config/routes.rb`
5. `config/settings.yml`
6. `config/locales/client.de.yml`
7. `config/locales/client.en.yml`
8. `config/locales/server.de.yml`
9. `config/locales/server.en.yml`
10. `app/controllers/vzekc_map/map_controller.rb`
11. `assets/stylesheets/vzekc-map.scss`
12. `assets/javascripts/discourse/vzekc-map-route-map.js`
13. `assets/javascripts/discourse/routes/member-map.js`
14. `assets/javascripts/discourse/templates/member-map.gjs`
15. `assets/javascripts/discourse/components/member-map.gjs`
