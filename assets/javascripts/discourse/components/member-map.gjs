import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import getURL from "discourse/lib/get-url";
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

export default class MemberMap extends Component {
  @service siteSettings;

  @tracked loading = true;
  @tracked error = null;

  map = null;
  markerCluster = null;

  get defaultCenter() {
    return [
      this.siteSettings.vzekc_map_default_center_lat || 51.1657,
      this.siteSettings.vzekc_map_default_center_lng || 10.4515,
    ];
  }

  get defaultZoom() {
    return this.siteSettings.vzekc_map_default_zoom || 6;
  }

  @action
  async setupMap(element) {
    try {
      await this.loadLeaflet();
      this.initializeMap(element);
      this.addMarkers();
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
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
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

    // Initialize marker cluster group
    this.markerCluster = L.markerClusterGroup({
      showCoverageOnHover: false,
      maxClusterRadius: 50,
    });

    this.map.addLayer(this.markerCluster);
  }

  addMarkers() {
    const L = window.L;
    const locations = this.args.locations || [];

    locations.forEach((location) => {
      const user = location.user;
      const coordinates = location.coordinates || [];

      coordinates.forEach((coord) => {
        const marker = L.marker([coord.lat, coord.lng]);

        // Create popup content with user info
        const avatarUrl = user.avatar_template.replace("{size}", "45");
        const userUrl = getURL(`/u/${user.username}`);
        const displayName = user.name || user.username;

        const popupContent = `
          <div class="member-map-popup">
            <a href="${userUrl}" class="member-map-popup-link">
              <img src="${avatarUrl}" alt="${displayName}" class="member-map-avatar" />
              <div class="member-map-user-info">
                <span class="member-map-username">${displayName}</span>
                ${user.name && user.name !== user.username ? `<span class="member-map-handle">@${user.username}</span>` : ""}
              </div>
            </a>
          </div>
        `;

        marker.bindPopup(popupContent);
        this.markerCluster.addLayer(marker);
      });
    });
  }

  <template>
    <div class="member-map-container">
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

      <div
        class="member-map-canvas"
        {{didInsert this.setupMap}}
        {{willDestroy this.destroyMap}}
      ></div>
    </div>
  </template>
}
