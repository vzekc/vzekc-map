# vzekc-map

A Discourse plugin that displays member locations on an interactive OpenStreetMap. Members can view where other members are located and manage their own location markers.

## Features

- **Interactive Map**: OpenStreetMap with Leaflet.js, showing member locations as markers
- **Multiple Locations**: Members can add multiple location markers (e.g., home, work, vacation home)
- **Location Search**: Search for places by name using Nominatim geocoding
- **Reverse Geocoding**: Automatically labels locations with city/postcode when adding markers
- **Points of Interest (POI)**: Display POI topics from a designated category on the map
- **WoltLab Sync**: Bi-directional location data sync with WoltLab Community Suite
- **Group-based Access Control**: Restrict map access to specific user groups

## Installation

1. Clone into your Discourse plugins directory:
   ```bash
   cd /var/discourse
   ./launcher enter app
   cd /var/www/discourse/plugins
   git clone https://github.com/vzekc/vzekc-map.git
   ```

2. Rebuild the container:
   ```bash
   cd /var/discourse
   ./launcher rebuild app
   ```

## Configuration

Navigate to **Admin > Settings** and search for `vzekc_map`:

| Setting | Default | Description |
|---------|---------|-------------|
| `vzekc_map_enabled` | `false` | Enable/disable the plugin |
| `vzekc_map_members_group_name` | `vereinsmitglieder` | Group whose members can access the map |
| `vzekc_map_default_center_lat` | `51.1657` | Default map center latitude (Germany) |
| `vzekc_map_default_center_lng` | `10.4515` | Default map center longitude |
| `vzekc_map_default_zoom` | `6` | Default zoom level (1-18) |
| `vzekc_map_poi_enabled` | `false` | Enable Points of Interest feature |
| `vzekc_map_poi_category_id` | - | Category containing POI topics |
| `vzekc_map_woltlab_sync_enabled` | `false` | Sync location changes to WoltLab |
| `vzekc_map_woltlab_sync_url` | - | WoltLab sync endpoint URL |
| `vzekc_map_woltlab_sync_secret` | - | Shared secret for API authentication |

## Usage

### Accessing the Map

Navigate to `/member-map` on your Discourse instance. Only members of the configured group can view the map.

### Viewing Locations

- Member markers are shown in blue
- Click a marker to see the member's name and avatar
- Click the username to visit their profile
- Use the layer control to toggle between map styles (Street/Satellite)

### Managing Your Locations

1. Click "Add Location" in the toolbar
2. Either:
   - Click directly on the map, or
   - Use the search box to find a place by name
3. Your location is saved with automatic city/postcode labeling
4. To delete a location, click your marker and select "Delete"

### Points of Interest

When enabled, POI topics appear as green markers. Create a POI by:

1. Navigate to the map and click "Add POI"
2. Click the desired location
3. A new topic is created in the POI category with the location embedded

## Data Model

### User Locations

Stored in `user_custom_fields` with name `Geoinformation`.

**Format**: Space-separated geo URIs
```
geo:52.535150,13.394236?z=19&name=10178%20Berlin geo:53.84893,10.71431?z=16&name=23552%20L%C3%BCbeck
```

**Supported input formats** (all parsed automatically):
- `geo:lat,lng?z=zoom&name=Name` (canonical)
- `geo:lat,lng?z=zoom`
- `geo:lat,lng`
- `lat,lng`
- OpenStreetMap URLs: `https://www.openstreetmap.org/?#map=zoom/lat/lng`

### POI Locations

Stored in `topic_custom_fields` with name `vzekc_map_coordinates`.

## API Endpoints

All endpoints require authentication and group membership.

### GET /vzekc-map/locations.json

Returns all member locations.

```json
{
  "locations": [
    {
      "user": {
        "id": 1,
        "username": "hans",
        "name": "Hans Hübner",
        "avatar_template": "/user_avatar/..."
      },
      "coordinates": [
        {"lat": 52.535, "lng": 13.394, "zoom": 19, "name": "10178 Berlin"}
      ]
    }
  ]
}
```

### POST /vzekc-map/locations.json

Add a new location for the current user.

**Parameters:**
- `lat` (float, required): Latitude
- `lng` (float, required): Longitude
- `zoom` (integer, optional): Zoom level

**Response:** Updated coordinates array

### DELETE /vzekc-map/locations/:index.json

Delete a location by index (0-based).

**Response:** Updated coordinates array

### GET /vzekc-map/pois.json

Returns all POI topics with coordinates.

```json
{
  "pois": [
    {
      "topic_id": 123,
      "title": "Computer Museum Berlin",
      "slug": "computer-museum-berlin",
      "coordinates": {"lat": 52.52, "lng": 13.40, "zoom": 15},
      "user": {"id": 1, "username": "hans", "avatar_template": "..."}
    }
  ]
}
```

## WoltLab Integration

The plugin can sync location changes back to a WoltLab Community Suite installation. This is useful during migration periods when user data flows from WoltLab to Discourse, but location changes in Discourse need to be reflected in WoltLab.

### Architecture

```
┌─────────────────────┐         ┌─────────────────────┐
│      Discourse      │         │       WoltLab       │
│                     │         │                     │
│  user_custom_fields │         │ wcf3_user_option_   │
│   "Geoinformation"  │         │   value.userOption47│
│                     │  HTTP   │                     │
│  ┌───────────────┐  │  POST   │  ┌───────────────┐  │
│  │ MapController │──┼────────►│  │sync_location  │  │
│  └───────────────┘  │         │  │    .php       │  │
│         │           │         │  └───────┬───────┘  │
│         ▼           │         │          │          │
│  ┌───────────────┐  │         │          ▼          │
│  │ WoltlabSync   │  │         │  ┌───────────────┐  │
│  │ (background)  │  │         │  │    MySQL      │  │
│  └───────────────┘  │         │  └───────────────┘  │
└─────────────────────┘         └─────────────────────┘
```

### How It Works

1. User updates their location in Discourse via the map interface
2. `MapController` saves to Discourse's `user_custom_fields`
3. `WoltlabSync` enqueues a background job
4. Job sends HTTP POST to WoltLab endpoint:
   ```
   POST /vzekc/sync_location.php
   X-Sync-Secret: <shared-secret>
   Content-Type: application/json

   {
     "username": "hans",
     "geoinformation": "geo:52.52,13.40?z=15&name=10178%20Berlin"
   }
   ```
5. PHP script validates secret, looks up user by username
6. Updates `userOption47` column in `wcf3_user_option_value`

### WoltLab Setup

1. **Deploy the sync endpoint:**
   ```bash
   cp woltlab/sync_location.php /var/www/forum/html/vzekc/
   ```

2. **Configure the shared secret** in `sync_location.php`:
   ```php
   define('DISCOURSE_SYNC_SECRET', 'your-64-char-hex-secret');
   ```

3. **Database configuration** is loaded automatically from WoltLab's `config.inc.php`

### WoltLab Data Model

| Item | Value |
|------|-------|
| User table | `wcf3_user` |
| Options table | `wcf3_user_option_value` |
| Geoinformation column | `userOption47` |
| Lookup field | `username` |

### Testing the Sync

```bash
# Test with httpie
http POST https://forum.example.com/vzekc/sync_location.php \
  X-Sync-Secret:your-secret \
  username=testuser \
  geoinformation='geo:52.52,13.40?z=15'

# Verify in MySQL
mysql -e "SELECT userOption47 FROM wcf3_user_option_value v
          JOIN wcf3_user u ON v.userID = u.userID
          WHERE u.username = 'testuser'" woltlab
```

### Security Considerations

- The sync endpoint is protected by a shared secret (64-character hex)
- Secret is sent via `X-Sync-Secret` header
- Consider restricting access by IP (Discourse server only) via nginx/Apache
- The endpoint only accepts POST requests
- User lookup is by username (must match between systems)

## Development

### Running Tests

```bash
cd /var/www/discourse
LOAD_PLUGINS=1 bundle exec rspec plugins/vzekc-map/spec
```

### File Structure

```
vzekc-map/
├── plugin.rb                     # Plugin initialization
├── config/
│   ├── routes.rb                 # API routes
│   ├── settings.yml              # Site settings
│   └── locales/                  # Translations (en, de)
├── app/
│   ├── controllers/vzekc_map/
│   │   └── map_controller.rb     # API endpoints
│   └── jobs/regular/
│       └── vzekc_map_woltlab_sync.rb  # Background sync job
├── lib/vzekc_map/
│   ├── engine.rb                 # Rails engine
│   ├── geo_parser.rb             # Coordinate parsing
│   ├── geocoder.rb               # Nominatim integration
│   ├── member_checker.rb         # Group membership
│   └── woltlab_sync.rb           # WoltLab sync service
├── assets/
│   ├── javascripts/discourse/
│   │   ├── components/member-map.gjs  # Map UI component
│   │   ├── routes/member-map.js       # Data loading
│   │   └── templates/member-map.gjs   # Page template
│   └── stylesheets/vzekc-map.scss
├── spec/                         # RSpec tests
└── woltlab/
    ├── sync_location.php         # WoltLab sync endpoint
    └── README.md                 # WoltLab setup docs
```

## License

MIT

## Author

Hans Hübner
