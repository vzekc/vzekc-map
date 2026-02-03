import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import icon from "discourse/helpers/d-icon";
import getURL from "discourse/lib/get-url";
import { not } from "truth-helpers";
import { i18n } from "discourse-i18n";

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

// Marker colors by POI type (for future extensibility)
const MARKER_COLORS = {
  member: "#2a9d8f", // teal for members
  // Future POI types can use different colors:
  // museum: "#8338ec",
  // event: "#e63946",
};

export default class MemberMap extends Component {
  @service siteSettings;
  @service currentUser;
  @service dialog;

  @tracked loading = true;
  @tracked error = null;
  @tracked hasHomeLocation = false;
  @tracked locations = [];
  @tracked isAddingLocation = false;

  map = null;
  markerCluster = null;
  mapClickHandler = null;
  escapeHandler = null;

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

  @action
  async setupMap(element) {
    try {
      this.locations = this.args.locations || [];
      this.hasHomeLocation = !!this.currentUserLocation;

      await this.loadLeaflet();
      this.initializeMap(element);
      this.restoreMapState();
      this.addMarkers();
      this.setupMapStateTracking();
      this.loading = false;
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error("Failed to initialize map:", e);
      this.error = e.message;
      this.loading = false;
    }
  }

  @action
  destroyMap() {
    this.saveMapState();
    this.exitAddingMode();
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
    };
    sessionStorage.setItem(MAP_STATE_KEY, JSON.stringify(state));
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
    const homeLoc = this.currentUserLocation;
    if (homeLoc && this.map) {
      this.map.setView([homeLoc.lat, homeLoc.lng], homeLoc.zoom || 15);
    }
  }

  @action
  resetView() {
    if (this.map) {
      this.map.setView(this.defaultCenter, this.defaultZoom);
    }
  }

  @action
  toggleAddLocation() {
    if (this.isAddingLocation) {
      this.exitAddingMode();
    } else {
      this.enterAddingMode();
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
      await this.saveNewLocation(e.latlng.lat, e.latlng.lng);
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

  async saveNewLocation(lat, lng) {
    const zoom = this.map.getZoom();

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
    }

    this.exitAddingMode();
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

    // Find or create current user's location entry
    let userLocIndex = this.locations.findIndex(
      (loc) => loc.user.id === this.currentUser.id
    );

    if (newCoordinates.length === 0) {
      // Remove user from locations if no coordinates
      if (userLocIndex >= 0) {
        this.locations.splice(userLocIndex, 1);
      }
    } else if (userLocIndex >= 0) {
      // Update existing entry
      this.locations[userLocIndex].coordinates = newCoordinates;
    } else {
      // Add new entry
      this.locations.push({
        user: {
          id: this.currentUser.id,
          username: this.currentUser.username,
          name: this.currentUser.name,
          avatar_template: this.currentUser.avatar_template,
        },
        coordinates: newCoordinates,
      });
    }

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

    this.map = L.map(element).setView(this.defaultCenter, this.defaultZoom);

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

    this.map.addLayer(this.markerCluster);
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

        // Handle click events
        marker.on("click", (e) => {
          // Don't navigate if in adding mode
          if (this.isAddingLocation) {
            return;
          }

          // Check if delete button was clicked (or any element inside it)
          const deleteBtn = e.originalEvent.target.closest(".member-map-marker-delete");
          if (deleteBtn) {
            e.originalEvent.stopPropagation();
            const deleteIndex = parseInt(deleteBtn.getAttribute("data-index"), 10);
            this.deleteLocation(deleteIndex);
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
          {{i18n "vzekc_map.click_to_add"}}
        </div>
      {{/if}}

      <div class="member-map-controls">
        <DButton
          @action={{this.resetView}}
          @icon="globe"
          @title="vzekc_map.reset_view"
          class="btn-default member-map-reset-btn"
        />
        <DButton
          @action={{this.goToHome}}
          @icon="house"
          @title={{if this.hasHomeLocation "vzekc_map.go_home" "vzekc_map.go_home_disabled"}}
          @disabled={{not this.hasHomeLocation}}
          class="btn-default member-map-home-btn"
        />
        <DButton
          @action={{this.toggleAddLocation}}
          @icon={{if this.isAddingLocation "xmark" "plus"}}
          @title={{if this.isAddingLocation "vzekc_map.cancel_add" "vzekc_map.add_location"}}
          class="btn-default member-map-add-btn {{if this.isAddingLocation 'is-adding'}}"
        />
      </div>

      <div
        class="member-map-canvas"
        {{didInsert this.setupMap}}
        {{willDestroy this.destroyMap}}
      ></div>
    </div>
  </template>
}
