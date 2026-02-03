import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import icon from "discourse/helpers/d-icon";
import getURL from "discourse/lib/get-url";
import { eq, not, and } from "truth-helpers";
import { i18n } from "discourse-i18n";
import Composer from "discourse/models/composer";

// Leaflet CDN URLs
const LEAFLET_CSS_URL = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
const LEAFLET_JS_URL = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
const MARKER_CLUSTER_CSS_URL =
  "https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.css";
const MARKER_CLUSTER_DEFAULT_CSS_URL =
  "https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.Default.css";
const MARKER_CLUSTER_JS_URL =
  "https://unpkg.com/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js";

// Storage key for map state
const MAP_STATE_KEY = "vzekc-map-state";

// Marker colors
const MARKER_COLORS = {
  member: "#2a9d8f", // teal for members
  poi: "#8338ec",    // purple for POIs
};

export default class MemberMap extends Component {
  @service siteSettings;
  @service currentUser;
  @service dialog;
  @service composer;

  @tracked loading = true;
  @tracked error = null;
  @tracked hasHomeLocation = false;
  @tracked locations = [];
  @tracked isAddingLocation = false;
  @tracked isSavingLocation = false;
  @tracked showLocationPicker = false;
  @tracked searchQuery = "";
  @tracked searchResults = [];
  @tracked isSearching = false;
  @tracked showSearchResults = false;
  @tracked showLayerMenu = false;
  @tracked layerMembers = true;
  @tracked layerPois = true;
  @tracked pois = [];
  @tracked showAddMenu = false;
  @tracked addingPoi = false;

  map = null;
  markerCluster = null;
  poiCluster = null;
  searchMarker = null;
  searchMarkerCleanupHandler = null;
  mapClickHandler = null;
  escapeHandler = null;
  locationPickerClickOutsideHandler = null;
  searchDebounceTimer = null;
  searchClickOutsideHandler = null;
  layerMenuClickOutsideHandler = null;
  addMenuClickOutsideHandler = null;

  get defaultCenter() {
    return [
      this.siteSettings.vzekc_map_default_center_lat || 51.1657,
      this.siteSettings.vzekc_map_default_center_lng || 10.4515,
    ];
  }

  get defaultZoom() {
    return this.siteSettings.vzekc_map_default_zoom || 6;
  }

  get currentUserLocation() {
    if (!this.currentUser) {
      return null;
    }
    const userLoc = this.locations.find(
      (loc) => loc.user.id === this.currentUser.id
    );
    return userLoc?.coordinates?.[0] || null;
  }

  get currentUserLocations() {
    if (!this.currentUser) {
      return [];
    }
    const userLoc = this.locations.find(
      (loc) => loc.user.id === this.currentUser.id
    );
    return userLoc?.coordinates || [];
  }

  get poiEnabled() {
    return this.siteSettings.vzekc_map_poi_enabled && this.siteSettings.vzekc_map_poi_category_id;
  }

  @action
  async setupMap(element) {
    try {
      this.locations = this.args.locations || [];
      this.hasHomeLocation = !!this.currentUserLocation;

      // Restore layer visibility from session storage
      this.restoreLayerState();

      await this.loadLeaflet();
      this.initializeMap(element);
      this.restoreMapState();
      this.addMarkers();
      await this.loadPois();
      this.setupMapStateTracking();

      // Check for POI parameter in URL and center map if present
      this.handlePoiUrlParameter();

      this.loading = false;
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error("Failed to initialize map:", e);
      this.error = e.message;
      this.loading = false;
    }
  }

  handlePoiUrlParameter() {
    const urlParams = new URLSearchParams(window.location.search);
    const poiParam = urlParams.get("poi");

    if (poiParam) {
      const parts = poiParam.split(",");
      if (parts.length >= 2) {
        const lat = parseFloat(parts[0]);
        const lng = parseFloat(parts[1]);
        const zoom = parts.length >= 3 ? parseInt(parts[2], 10) : 15;

        if (!isNaN(lat) && !isNaN(lng)) {
          this.map.setView([lat, lng], zoom);

          // Clear the URL parameter without reloading
          const url = new URL(window.location);
          url.searchParams.delete("poi");
          window.history.replaceState({}, "", url);
        }
      }
    }
  }

  @action
  destroyMap() {
    this.saveMapState();
    this.exitAddingMode();
    this.cleanupLocationPickerClickOutside();
    this.cleanupSearchClickOutside();
    this.cleanupLayerMenuClickOutside();
    this.cleanupAddMenuClickOutside();
    if (this.searchDebounceTimer) {
      clearTimeout(this.searchDebounceTimer);
      this.searchDebounceTimer = null;
    }
    if (this.deleteClickHandler && this.map) {
      this.map.getContainer().removeEventListener("click", this.deleteClickHandler, true);
      this.deleteClickHandler = null;
    }
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }

  saveMapState() {
    if (!this.map) {
      return;
    }
    const center = this.map.getCenter();
    const zoom = this.map.getZoom();
    const state = {
      lat: center.lat,
      lng: center.lng,
      zoom: zoom,
      layerMembers: this.layerMembers,
      layerPois: this.layerPois,
    };
    sessionStorage.setItem(MAP_STATE_KEY, JSON.stringify(state));
  }

  restoreLayerState() {
    const savedState = sessionStorage.getItem(MAP_STATE_KEY);
    if (savedState) {
      try {
        const state = JSON.parse(savedState);
        if (typeof state.layerMembers === "boolean") {
          this.layerMembers = state.layerMembers;
        }
        if (typeof state.layerPois === "boolean") {
          this.layerPois = state.layerPois;
        }
      } catch (e) {
        // Ignore invalid state
      }
    }
  }

  restoreMapState() {
    const savedState = sessionStorage.getItem(MAP_STATE_KEY);
    if (savedState) {
      try {
        const state = JSON.parse(savedState);
        this.map.setView([state.lat, state.lng], state.zoom);
      } catch (e) {
        // Ignore invalid state
      }
    }
  }

  setupMapStateTracking() {
    // Save state when map moves or zooms
    this.map.on("moveend", () => this.saveMapState());
    this.map.on("zoomend", () => this.saveMapState());
  }

  @action
  goToHome() {
    const userLocations = this.currentUserLocations;
    if (!userLocations.length || !this.map) {
      return;
    }

    // If only one location, go directly with smart zoom
    if (userLocations.length === 1) {
      this.goToLocationWithSmartZoom(userLocations[0]);
      return;
    }

    // Multiple locations - show picker
    this.showLocationPicker = true;
    this.setupLocationPickerClickOutside();
  }

  @action
  selectLocation(location) {
    this.hideLocationPicker();
    this.goToLocationWithSmartZoom(location);
  }

  @action
  hideLocationPicker() {
    this.showLocationPicker = false;
    this.cleanupLocationPickerClickOutside();
  }

  setupLocationPickerClickOutside() {
    // Close picker when clicking outside
    this.locationPickerClickOutsideHandler = (e) => {
      if (!e.target.closest(".member-map-location-picker") &&
          !e.target.closest(".member-map-home-btn")) {
        this.hideLocationPicker();
      }
    };
    // Use setTimeout to avoid immediate trigger from the button click
    setTimeout(() => {
      document.addEventListener("click", this.locationPickerClickOutsideHandler);
    }, 0);
  }

  cleanupLocationPickerClickOutside() {
    if (this.locationPickerClickOutsideHandler) {
      document.removeEventListener("click", this.locationPickerClickOutsideHandler);
      this.locationPickerClickOutsideHandler = null;
    }
  }

  goToLocationWithSmartZoom(targetLocation) {
    if (!this.map || !targetLocation) {
      return;
    }

    const L = window.L;
    const targetLatLng = L.latLng(targetLocation.lat, targetLocation.lng);

    // Find nearest other member (excluding current user's locations)
    const nearestNeighbor = this.findNearestNeighbor(targetLatLng);

    if (nearestNeighbor) {
      // Fit bounds to show both target and nearest neighbor
      const bounds = L.latLngBounds([targetLatLng, nearestNeighbor]);
      this.map.fitBounds(bounds, {
        padding: [50, 50],
        maxZoom: 15,
      });
    } else {
      // No other members, just center on target with saved zoom or default
      this.map.setView(targetLatLng, targetLocation.zoom || 12);
    }
  }

  findNearestNeighbor(targetLatLng) {
    const L = window.L;
    let nearestLatLng = null;
    let nearestDistance = Infinity;

    this.locations.forEach((location) => {
      // Skip current user's locations
      if (location.user.id === this.currentUser?.id) {
        return;
      }

      location.coordinates?.forEach((coord) => {
        const coordLatLng = L.latLng(coord.lat, coord.lng);
        const distance = targetLatLng.distanceTo(coordLatLng);

        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestLatLng = coordLatLng;
        }
      });
    });

    return nearestLatLng;
  }

  getLocationDisplayName(location) {
    if (location.name) {
      return location.name;
    }
    // Fallback to coordinates if no name
    return `${location.lat.toFixed(4)}, ${location.lng.toFixed(4)}`;
  }

  @action
  onSearchInput(event) {
    const query = event.target.value;
    this.searchQuery = query;

    // Clear previous timer
    if (this.searchDebounceTimer) {
      clearTimeout(this.searchDebounceTimer);
    }

    if (query.length < 2) {
      this.searchResults = [];
      this.showSearchResults = false;
      return;
    }

    // Debounce search
    this.searchDebounceTimer = setTimeout(() => {
      this.performSearch(query);
    }, 300);
  }

  @action
  onSearchFocus() {
    if (this.searchQuery.length >= 2 && this.searchResults.length > 0) {
      this.showSearchResults = true;
      this.setupSearchClickOutside();
    }
  }

  @action
  onSearchKeydown(event) {
    if (event.key === "Escape") {
      this.hideSearchResults();
      event.target.blur();
    }
  }

  async performSearch(query) {
    this.isSearching = true;
    this.showSearchResults = true;
    this.setupSearchClickOutside();

    const results = [];
    const queryLower = query.toLowerCase();

    // Search members by username - include all locations for each matching user
    this.locations.forEach((location) => {
      if (location.user.username.toLowerCase().includes(queryLower)) {
        location.coordinates?.forEach((coord) => {
          results.push({
            type: "member",
            label: `@${location.user.username}`,
            sublabel: coord.name || `${coord.lat.toFixed(4)}, ${coord.lng.toFixed(4)}`,
            lat: coord.lat,
            lng: coord.lng,
            zoom: coord.zoom,
          });
        });
      }
    });

    // Search POIs by title
    if (this.poiEnabled) {
      this.pois.forEach((poi) => {
        if (poi.title.toLowerCase().includes(queryLower)) {
          results.push({
            type: "poi",
            label: poi.title,
            sublabel: poi.coordinates.name || `${poi.coordinates.lat.toFixed(4)}, ${poi.coordinates.lng.toFixed(4)}`,
            lat: poi.coordinates.lat,
            lng: poi.coordinates.lng,
            zoom: poi.coordinates.zoom || 15,
            topicUrl: `/t/${poi.slug}/${poi.topic_id}`,
          });
        }
      });
    }

    // Search places via Nominatim
    try {
      const placeResults = await this.searchPlaces(query);
      results.push(...placeResults);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error("Place search failed:", e);
    }

    this.searchResults = results;
    this.isSearching = false;
  }

  async searchPlaces(query) {
    const url = new URL("https://nominatim.openstreetmap.org/search");
    url.searchParams.set("q", query);
    url.searchParams.set("format", "json");
    url.searchParams.set("limit", "5");
    url.searchParams.set("addressdetails", "1");
    // Bias towards Germany/Europe
    url.searchParams.set("viewbox", "-10,35,30,60");
    url.searchParams.set("bounded", "0");

    const response = await fetch(url, {
      headers: {
        "Accept-Language": "de,en",
      },
    });

    if (!response.ok) {
      return [];
    }

    const data = await response.json();
    return data.map((item) => ({
      type: "place",
      label: item.display_name.split(",").slice(0, 2).join(","),
      sublabel: item.display_name.split(",").slice(2, 4).join(",").trim(),
      lat: parseFloat(item.lat),
      lng: parseFloat(item.lon),
      zoom: this.getZoomForPlaceType(item.type, item.class),
    }));
  }

  getZoomForPlaceType(type, placeClass) {
    // Return appropriate zoom level based on place type
    if (type === "house" || type === "building") return 18;
    if (type === "street" || type === "road") return 16;
    if (type === "suburb" || type === "neighbourhood") return 14;
    if (type === "city" || type === "town") return 12;
    if (type === "county" || type === "state") return 9;
    if (placeClass === "boundary") return 10;
    return 13;
  }

  @action
  selectSearchResult(result) {
    this.hideSearchResults();
    this.searchQuery = "";

    if (this.map) {
      const L = window.L;
      const targetLatLng = L.latLng(result.lat, result.lng);

      // Remove any existing search marker
      this.removeSearchMarker();

      // Determine zoom level - ensure minimum of 15 for adding locations
      const minZoomForAdding = 15;
      let targetZoom = result.zoom || 15;

      if (result.type === "member") {
        // For members, use smart zoom but ensure minimum zoom
        const nearestNeighbor = this.findNearestNeighborExcluding(targetLatLng, result.label.slice(1));
        if (nearestNeighbor) {
          const bounds = L.latLngBounds([targetLatLng, nearestNeighbor]);
          this.map.fitBounds(bounds, { padding: [50, 50], maxZoom: minZoomForAdding });
          // After fitBounds, check if zoom is too low
          if (this.map.getZoom() < minZoomForAdding) {
            this.map.setView(targetLatLng, minZoomForAdding);
          }
        } else {
          this.map.setView(targetLatLng, Math.max(targetZoom, minZoomForAdding));
        }
      } else if (result.type === "poi") {
        // For POIs, zoom in appropriately
        this.map.setView(targetLatLng, Math.max(targetZoom, minZoomForAdding));
      } else {
        // For places, zoom to the location with minimum zoom
        this.map.setView(targetLatLng, Math.max(targetZoom, minZoomForAdding));
      }

      // Add search marker to indicate the location
      this.addSearchMarker(targetLatLng);
    }
  }

  addSearchMarker(latLng) {
    const L = window.L;

    // Create a small red pin marker
    const markerIcon = L.divIcon({
      className: "search-result-marker",
      html: `<div class="search-result-marker-pin"></div>`,
      iconSize: [16, 24],
      iconAnchor: [8, 24],
    });

    this.searchMarker = L.marker(latLng, { icon: markerIcon });
    this.searchMarker.addTo(this.map);

    // Remove marker when map is moved or zoomed
    this.searchMarkerCleanupHandler = () => {
      this.removeSearchMarker();
    };
    this.map.once("movestart", this.searchMarkerCleanupHandler);
    this.map.once("zoomstart", this.searchMarkerCleanupHandler);
  }

  removeSearchMarker() {
    if (this.searchMarker) {
      this.map.removeLayer(this.searchMarker);
      this.searchMarker = null;
    }
    if (this.searchMarkerCleanupHandler) {
      this.map.off("movestart", this.searchMarkerCleanupHandler);
      this.map.off("zoomstart", this.searchMarkerCleanupHandler);
      this.searchMarkerCleanupHandler = null;
    }
  }

  findNearestNeighborExcluding(targetLatLng, excludeUsername) {
    const L = window.L;
    let nearestLatLng = null;
    let nearestDistance = Infinity;

    this.locations.forEach((location) => {
      if (location.user.username === excludeUsername) {
        return;
      }

      location.coordinates?.forEach((coord) => {
        const coordLatLng = L.latLng(coord.lat, coord.lng);
        const distance = targetLatLng.distanceTo(coordLatLng);

        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestLatLng = coordLatLng;
        }
      });
    });

    return nearestLatLng;
  }

  hideSearchResults() {
    this.showSearchResults = false;
    this.cleanupSearchClickOutside();
  }

  setupSearchClickOutside() {
    if (this.searchClickOutsideHandler) return;

    this.searchClickOutsideHandler = (e) => {
      if (!e.target.closest(".member-map-search")) {
        this.hideSearchResults();
      }
    };
    setTimeout(() => {
      document.addEventListener("click", this.searchClickOutsideHandler);
    }, 0);
  }

  cleanupSearchClickOutside() {
    if (this.searchClickOutsideHandler) {
      document.removeEventListener("click", this.searchClickOutsideHandler);
      this.searchClickOutsideHandler = null;
    }
  }

  // Layer control methods
  @action
  toggleLayerMenu() {
    this.showLayerMenu = !this.showLayerMenu;
    if (this.showLayerMenu) {
      this.setupLayerMenuClickOutside();
    } else {
      this.cleanupLayerMenuClickOutside();
    }
  }

  @action
  hideLayerMenu() {
    this.showLayerMenu = false;
    this.cleanupLayerMenuClickOutside();
  }

  setupLayerMenuClickOutside() {
    this.layerMenuClickOutsideHandler = (e) => {
      if (!e.target.closest(".member-map-layer-container")) {
        this.hideLayerMenu();
      }
    };
    setTimeout(() => {
      document.addEventListener("click", this.layerMenuClickOutsideHandler);
    }, 0);
  }

  cleanupLayerMenuClickOutside() {
    if (this.layerMenuClickOutsideHandler) {
      document.removeEventListener("click", this.layerMenuClickOutsideHandler);
      this.layerMenuClickOutsideHandler = null;
    }
  }

  @action
  toggleMemberLayer(event) {
    this.layerMembers = event.target.checked;
    this.updateLayerVisibility();
    this.saveMapState();
  }

  @action
  togglePoiLayer(event) {
    this.layerPois = event.target.checked;
    this.updateLayerVisibility();
    this.saveMapState();
  }

  updateLayerVisibility() {
    if (!this.map) return;

    if (this.markerCluster) {
      if (this.layerMembers) {
        this.map.addLayer(this.markerCluster);
      } else {
        this.map.removeLayer(this.markerCluster);
      }
    }

    if (this.poiCluster) {
      if (this.layerPois) {
        this.map.addLayer(this.poiCluster);
      } else {
        this.map.removeLayer(this.poiCluster);
      }
    }
  }

  // POI loading and display
  async loadPois() {
    if (!this.poiEnabled) return;

    try {
      const result = await ajax("/vzekc-map/pois.json");
      this.pois = result.pois || [];
      this.addPoiMarkers();
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error("Failed to load POIs:", e);
    }
  }

  addPoiMarkers() {
    if (!this.poiCluster || !this.pois.length) return;

    const L = window.L;
    const poiColor = MARKER_COLORS.poi;

    this.pois.forEach((poi) => {
      const markerIcon = L.divIcon({
        className: "poi-map-marker",
        html: `
          <div class="poi-map-marker-label" style="background-color: ${poiColor}">
            ${this.escapeHtml(poi.title)}
            <span class="poi-map-marker-arrow" style="border-top-color: ${poiColor}"></span>
          </div>
        `,
        iconSize: null,
        iconAnchor: [0, 0],
      });

      const marker = L.marker([poi.coordinates.lat, poi.coordinates.lng], { icon: markerIcon });
      const topicUrl = getURL(`/t/${poi.slug}/${poi.topic_id}`);

      // Show popup on click with POI info
      marker.bindPopup(`
        <div class="poi-popup">
          <strong>${this.escapeHtml(poi.title)}</strong>
          <p>by @${this.escapeHtml(poi.user.username)}</p>
          <a href="${topicUrl}">Open discussion</a>
        </div>
      `);

      this.poiCluster.addLayer(marker);
    });

    if (this.layerPois) {
      this.map.addLayer(this.poiCluster);
    }
  }

  // Add menu methods
  @action
  toggleAddMenu() {
    if (this.isAddingLocation) {
      this.exitAddingMode();
      return;
    }

    // If POI is not enabled, directly start adding home location
    if (!this.poiEnabled) {
      this.startAddHomeLocation();
      return;
    }

    this.showAddMenu = !this.showAddMenu;
    if (this.showAddMenu) {
      this.setupAddMenuClickOutside();
    } else {
      this.cleanupAddMenuClickOutside();
    }
  }

  @action
  hideAddMenu() {
    this.showAddMenu = false;
    this.cleanupAddMenuClickOutside();
  }

  setupAddMenuClickOutside() {
    this.addMenuClickOutsideHandler = (e) => {
      if (!e.target.closest(".member-map-add-container")) {
        this.hideAddMenu();
      }
    };
    setTimeout(() => {
      document.addEventListener("click", this.addMenuClickOutsideHandler);
    }, 0);
  }

  cleanupAddMenuClickOutside() {
    if (this.addMenuClickOutsideHandler) {
      document.removeEventListener("click", this.addMenuClickOutsideHandler);
      this.addMenuClickOutsideHandler = null;
    }
  }

  @action
  startAddHomeLocation() {
    this.hideAddMenu();
    this.addingPoi = false;
    this.enterAddingMode();
  }

  @action
  startAddPoi() {
    this.hideAddMenu();
    this.addingPoi = true;
    this.enterAddingMode();
  }

  @action
  resetView() {
    if (this.map) {
      this.map.setView(this.defaultCenter, this.defaultZoom);
    }
  }

  enterAddingMode() {
    if (!this.map) {
      return;
    }

    this.isAddingLocation = true;

    // Change cursor to crosshair
    this.map.getContainer().style.cursor = "crosshair";

    // Listen for map clicks
    this.mapClickHandler = async (e) => {
      if (this.addingPoi) {
        await this.addPoi(e.latlng.lat, e.latlng.lng);
      } else {
        await this.saveNewLocation(e.latlng.lat, e.latlng.lng);
      }
    };
    this.map.on("click", this.mapClickHandler);

    // Listen for Escape key to cancel
    this.escapeHandler = (e) => {
      if (e.key === "Escape") {
        this.exitAddingMode();
      }
    };
    document.addEventListener("keydown", this.escapeHandler);
  }

  exitAddingMode() {
    this.isAddingLocation = false;
    this.addingPoi = false;

    if (this.map) {
      this.map.getContainer().style.cursor = "";

      if (this.mapClickHandler) {
        this.map.off("click", this.mapClickHandler);
        this.mapClickHandler = null;
      }
    }

    if (this.escapeHandler) {
      document.removeEventListener("keydown", this.escapeHandler);
      this.escapeHandler = null;
    }
  }

  async addPoi(lat, lng) {
    const zoom = this.map.getZoom();
    const geoUri = `geo:${lat},${lng}?z=${zoom}`;

    this.exitAddingMode();

    // Reverse geocode to get location name suggestion
    let suggestedTitle = `POI at ${lat.toFixed(4)}, ${lng.toFixed(4)}`;
    try {
      const geocodeResult = await this.reverseGeocode(lat, lng);
      if (geocodeResult?.name) {
        suggestedTitle = geocodeResult.name;
      }
    } catch (e) {
      // Use default title if geocoding fails
    }

    // Build map link with coordinates
    const mapLink = `/member-map?poi=${lat},${lng},${zoom}`;

    // Build template using i18n
    const t = (key) => i18n(`vzekc_map.poi_template.${key}`);
    const template = `${t("location_heading")}
[${t("view_on_map")}](${mapLink})

${t("description_heading")}
${t("description_hint")}

${t("details_heading")}
${t("details_hint")}

${t("contact_heading")}
${t("contact_hint")}

${t("warning")}
`;

    // Use a unique draft key to avoid conflicts with other drafts
    const draftKey = `poi_${Date.now()}`;

    this.composer.open({
      action: Composer.CREATE_TOPIC,
      categoryId: parseInt(this.siteSettings.vzekc_map_poi_category_id, 10),
      draftKey: draftKey,
      title: suggestedTitle,
      topicBody: template,
      skipDraftCheck: true,
    });
  }

  async reverseGeocode(lat, lng) {
    const url = new URL("https://nominatim.openstreetmap.org/reverse");
    url.searchParams.set("lat", lat.toString());
    url.searchParams.set("lon", lng.toString());
    url.searchParams.set("format", "json");
    url.searchParams.set("addressdetails", "1");

    const response = await fetch(url, {
      headers: {
        "Accept-Language": "de,en",
      },
    });

    if (!response.ok) {
      return null;
    }

    const data = await response.json();
    if (data?.address) {
      const parts = [];
      if (data.address.road) parts.push(data.address.road);
      if (data.address.city || data.address.town || data.address.village) {
        parts.push(data.address.city || data.address.town || data.address.village);
      }
      return { name: parts.join(", ") || data.display_name?.split(",").slice(0, 2).join(",") };
    }
    return null;
  }

  async saveNewLocation(lat, lng) {
    const zoom = this.map.getZoom();

    this.isSavingLocation = true;
    this.exitAddingMode();

    try {
      const result = await ajax("/vzekc-map/locations.json", {
        type: "POST",
        data: { lat, lng, zoom },
      });

      // Update local state
      this.updateCurrentUserCoordinates(result.coordinates);
      this.rebuildMarkers();
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.isSavingLocation = false;
    }
  }

  @action
  async deleteLocation(index) {
    this.dialog.confirm({
      message: i18n("vzekc_map.delete_location_confirm"),
      didConfirm: async () => {
        try {
          const result = await ajax(`/vzekc-map/locations/${index}.json`, {
            type: "DELETE",
          });

          // Update local state
          this.updateCurrentUserCoordinates(result.coordinates);
          this.rebuildMarkers();
        } catch (e) {
          popupAjaxError(e);
        }
      },
    });
  }

  updateCurrentUserCoordinates(newCoordinates) {
    if (!this.currentUser) {
      return;
    }

    // Find current user's location entry
    const userLocIndex = this.locations.findIndex(
      (loc) => loc.user.id === this.currentUser.id
    );

    // Create a new array to trigger Glimmer reactivity
    let updatedLocations = [...this.locations];

    if (newCoordinates.length === 0) {
      // Remove user from locations if no coordinates
      if (userLocIndex >= 0) {
        updatedLocations.splice(userLocIndex, 1);
      }
    } else if (userLocIndex >= 0) {
      // Update existing entry with new object reference
      updatedLocations[userLocIndex] = {
        ...updatedLocations[userLocIndex],
        coordinates: newCoordinates,
      };
    } else {
      // Add new entry
      updatedLocations.push({
        user: {
          id: this.currentUser.id,
          username: this.currentUser.username,
          name: this.currentUser.name,
          avatar_template: this.currentUser.avatar_template,
        },
        coordinates: newCoordinates,
      });
    }

    this.locations = updatedLocations;
    this.hasHomeLocation = newCoordinates.length > 0;
  }

  rebuildMarkers() {
    if (!this.markerCluster) {
      return;
    }
    this.markerCluster.clearLayers();
    this.addMarkers();
  }

  async loadLeaflet() {
    // Return if already loaded
    if (window.L?.markerClusterGroup) {
      return;
    }

    // Load CSS files
    await Promise.all([
      this.loadCSS(LEAFLET_CSS_URL),
      this.loadCSS(MARKER_CLUSTER_CSS_URL),
      this.loadCSS(MARKER_CLUSTER_DEFAULT_CSS_URL),
    ]);

    // Load Leaflet JS first
    if (!window.L) {
      await this.loadScript(LEAFLET_JS_URL);
    }

    // Then load marker cluster plugin
    if (!window.L.markerClusterGroup) {
      await this.loadScript(MARKER_CLUSTER_JS_URL);
    }
  }

  loadCSS(url) {
    return new Promise((resolve, reject) => {
      // Check if already loaded
      if (document.querySelector(`link[href="${url}"]`)) {
        resolve();
        return;
      }

      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = url;
      link.onload = resolve;
      link.onerror = () => reject(new Error(`Failed to load CSS: ${url}`));
      document.head.appendChild(link);
    });
  }

  loadScript(url) {
    return new Promise((resolve, reject) => {
      // Check if already loaded
      if (document.querySelector(`script[src="${url}"]`)) {
        resolve();
        return;
      }

      const script = document.createElement("script");
      script.src = url;
      script.onload = resolve;
      script.onerror = () => reject(new Error(`Failed to load script: ${url}`));
      document.head.appendChild(script);
    });
  }

  initializeMap(element) {
    const L = window.L;

    this.map = L.map(element, {
      zoomControl: false, // We'll add it in a different position
    }).setView(this.defaultCenter, this.defaultZoom);

    // Add zoom control to bottom-right
    L.control.zoom({ position: "bottomright" }).addTo(this.map);

    // Add OpenStreetMap tile layer
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(this.map);

    // Initialize marker cluster group with custom cluster icons
    this.markerCluster = L.markerClusterGroup({
      showCoverageOnHover: false,
      maxClusterRadius: 50,
      iconCreateFunction: (cluster) => {
        const count = cluster.getChildCount();
        return L.divIcon({
          html: `<div class="member-map-cluster">${count}</div>`,
          className: "member-map-cluster-icon",
          iconSize: L.point(36, 36),
        });
      },
    });

    if (this.layerMembers) {
      this.map.addLayer(this.markerCluster);
    }

    // Initialize POI cluster group with different style
    this.poiCluster = L.markerClusterGroup({
      showCoverageOnHover: false,
      maxClusterRadius: 50,
      iconCreateFunction: (cluster) => {
        const count = cluster.getChildCount();
        return L.divIcon({
          html: `<div class="poi-map-cluster">${count}</div>`,
          className: "poi-map-cluster-icon",
          iconSize: L.point(36, 36),
        });
      },
    });

    // Use event delegation for delete buttons - captures clicks before marker events
    this.deleteClickHandler = (e) => {
      const deleteBtn = e.target.closest(".member-map-marker-delete");
      if (deleteBtn) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        const deleteIndex = parseInt(deleteBtn.getAttribute("data-index"), 10);
        this.deleteLocation(deleteIndex);
      }
    };
    element.addEventListener("click", this.deleteClickHandler, true); // Use capture phase
  }

  addMarkers() {
    const L = window.L;
    const markerColor = MARKER_COLORS.member;
    const currentUserId = this.currentUser?.id;

    this.locations.forEach((location) => {
      const user = location.user;
      const coordinates = location.coordinates || [];
      const userUrl = getURL(`/u/${user.username}`);
      const isOwnMarker = user.id === currentUserId;

      coordinates.forEach((coord, index) => {
        // Create custom icon with @username (and delete button for own markers)
        // Using inline SVG path for the X icon since <use> doesn't work in dynamic HTML
        const deleteButton = isOwnMarker
          ? `<span class="member-map-marker-delete" data-index="${index}" title="${i18n("vzekc_map.delete_location")}"><svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><path d="M1 1l8 8M9 1l-8 8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></span>`
          : "";

        const markerIcon = L.divIcon({
          className: `member-map-marker ${isOwnMarker ? "member-map-marker-own" : ""}`,
          html: `
            <div class="member-map-marker-label" style="background-color: ${markerColor}">
              @${this.escapeHtml(user.username)}
              ${deleteButton}
              <span class="member-map-marker-arrow" style="border-top-color: ${markerColor}"></span>
            </div>
          `,
          iconSize: null,
          iconAnchor: [0, 0],
        });

        const marker = L.marker([coord.lat, coord.lng], { icon: markerIcon });

        // Handle click events - delete button clicks are handled by event delegation
        marker.on("click", (e) => {
          // Don't navigate if in adding mode
          if (this.isAddingLocation) {
            return;
          }

          // Don't navigate if click was on delete button (handled by delegation)
          if (e.originalEvent.target.closest(".member-map-marker-delete")) {
            return;
          }

          // Navigate to user profile
          window.location.href = userUrl;
        });

        this.markerCluster.addLayer(marker);
      });
    });
  }

  // Escape HTML to prevent XSS in marker labels
  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  <template>
    <div class="member-map-container {{if this.isAddingLocation 'adding-mode'}}">
      {{#if this.loading}}
        <div class="member-map-loading">
          {{icon "spinner" class="spinner"}}
          {{i18n "vzekc_map.loading"}}
        </div>
      {{/if}}

      {{#if this.error}}
        <div class="member-map-error">
          {{i18n "vzekc_map.errors.load_failed"}}: {{this.error}}
        </div>
      {{/if}}

      {{#if this.isAddingLocation}}
        <div class="member-map-adding-hint">
          {{icon "location-crosshairs"}}
          {{#if this.addingPoi}}
            {{i18n "vzekc_map.click_to_add_poi"}}
          {{else}}
            {{i18n "vzekc_map.click_to_add"}}
          {{/if}}
        </div>
      {{/if}}

      {{#if this.isSavingLocation}}
        <div class="member-map-saving-hint">
          {{icon "spinner" class="spinner"}}
          {{i18n "vzekc_map.saving_location"}}
        </div>
      {{/if}}

      <div class="member-map-toolbar">
        <div class="member-map-search">
          <div class="member-map-search-input-wrapper">
            {{icon "magnifying-glass" class="search-icon"}}
            <input
              type="text"
              class="member-map-search-input"
              placeholder={{i18n "vzekc_map.search_placeholder"}}
              value={{this.searchQuery}}
              autocomplete="off"
              {{on "input" this.onSearchInput}}
              {{on "focus" this.onSearchFocus}}
              {{on "keydown" this.onSearchKeydown}}
            />
            {{#if this.isSearching}}
              {{icon "spinner" class="spinner search-spinner"}}
            {{/if}}
          </div>
          {{#if this.showSearchResults}}
            <div class="member-map-search-results">
              {{#if this.searchResults.length}}
                {{#each this.searchResults as |result|}}
                  <button
                    type="button"
                    class="member-map-search-result"
                    {{on "click" (fn this.selectSearchResult result)}}
                  >
                    {{#if (eq result.type "member")}}
                      {{icon "user"}}
                    {{else if (eq result.type "poi")}}
                      {{icon "map-pin"}}
                    {{else}}
                      {{icon "map-marker-alt"}}
                    {{/if}}
                    <div class="search-result-text">
                      <span class="search-result-label">{{result.label}}</span>
                      {{#if result.sublabel}}
                        <span class="search-result-sublabel">{{result.sublabel}}</span>
                      {{/if}}
                    </div>
                  </button>
                {{/each}}
              {{else if (not this.isSearching)}}
                <div class="member-map-search-no-results">
                  {{i18n "vzekc_map.search_no_results"}}
                </div>
              {{/if}}
            </div>
          {{/if}}
        </div>

        <div class="member-map-controls">
          {{#if this.poiEnabled}}
            <div class="member-map-layer-container">
              <DButton
                @action={{this.toggleLayerMenu}}
                @icon="layer-group"
                @title="vzekc_map.layers"
                class="btn-default member-map-control-btn"
              />
              {{#if this.showLayerMenu}}
                <div class="member-map-layer-menu">
                  <label class="member-map-layer-option">
                    <input
                      type="checkbox"
                      checked={{this.layerMembers}}
                      {{on "change" this.toggleMemberLayer}}
                    />
                    <span>{{i18n "vzekc_map.layer_members"}}</span>
                  </label>
                  <label class="member-map-layer-option">
                    <input
                      type="checkbox"
                      checked={{this.layerPois}}
                      {{on "change" this.togglePoiLayer}}
                    />
                    <span>{{i18n "vzekc_map.layer_pois"}}</span>
                  </label>
                </div>
              {{/if}}
            </div>
          {{/if}}
          <DButton
            @action={{this.resetView}}
            @icon="globe"
            @title="vzekc_map.reset_view"
            class="btn-default member-map-control-btn"
          />
          <div class="member-map-home-container">
            <DButton
              @action={{this.goToHome}}
              @icon="house"
              @title={{if this.hasHomeLocation "vzekc_map.go_home" "vzekc_map.go_home_disabled"}}
              @disabled={{not this.hasHomeLocation}}
              class="btn-default member-map-control-btn"
            />
            {{#if this.showLocationPicker}}
              <div class="member-map-location-picker">
                {{#each this.currentUserLocations as |location index|}}
                  <button
                    type="button"
                    class="member-map-location-option"
                    {{on "click" (fn this.selectLocation location)}}
                  >
                    {{icon "map-marker-alt"}}
                    <span class="location-name">{{this.getLocationDisplayName location}}</span>
                  </button>
                {{/each}}
              </div>
            {{/if}}
          </div>
          <div class="member-map-add-container">
            <DButton
              @action={{this.toggleAddMenu}}
              @icon={{if this.isAddingLocation "xmark" "plus"}}
              @title={{if this.isAddingLocation "vzekc_map.cancel_add" "vzekc_map.add_location"}}
              class="btn-default member-map-control-btn {{if this.isAddingLocation 'is-adding'}}"
            />
            {{#if (and this.showAddMenu this.poiEnabled)}}
              <div class="member-map-add-menu">
                <button
                  type="button"
                  class="member-map-add-option"
                  {{on "click" this.startAddHomeLocation}}
                >
                  {{icon "house"}}
                  <span>{{i18n "vzekc_map.add_home_location"}}</span>
                </button>
                <button
                  type="button"
                  class="member-map-add-option"
                  {{on "click" this.startAddPoi}}
                >
                  {{icon "map-pin"}}
                  <span>{{i18n "vzekc_map.add_poi"}}</span>
                </button>
              </div>
            {{/if}}
          </div>
        </div>
      </div>

      <div
        class="member-map-canvas"
        {{didInsert this.setupMap}}
        {{willDestroy this.destroyMap}}
      ></div>
    </div>
  </template>
}
