import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "truth-helpers";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class VzekcMapProfileLinks extends Component {
  @tracked showLocationDropdown = false;
  @tracked selectedLocationIndex = 0;

  clickOutsideHandler = null;

  get locations() {
    return this.args.outletArgs.model?.vzekc_map_locations || [];
  }

  get hasLocations() {
    return this.locations.length > 0;
  }

  get hasMultipleLocations() {
    return this.locations.length > 1;
  }

  get currentLocation() {
    return this.locations[this.selectedLocationIndex];
  }

  get locationLabel() {
    const loc = this.currentLocation;
    if (!loc) return "";
    if (loc.name) return loc.name;
    return `${loc.lat.toFixed(4)}, ${loc.lng.toFixed(4)}`;
  }

  googleMapsUrl(loc) {
    return `https://www.google.com/maps?q=${loc.lat},${loc.lng}`;
  }

  appleMapsUrl(loc) {
    const name = loc.name ? encodeURIComponent(loc.name) : "";
    return `https://maps.apple.com/?ll=${loc.lat},${loc.lng}&q=${name}`;
  }

  openStreetMapUrl(loc) {
    const zoom = loc.zoom || 15;
    return `https://www.openstreetmap.org/?mlat=${loc.lat}&mlon=${loc.lng}&zoom=${zoom}`;
  }

  @action
  toggleLocationDropdown() {
    this.showLocationDropdown = !this.showLocationDropdown;
    if (this.showLocationDropdown) {
      this.setupClickOutside();
    } else {
      this.cleanupClickOutside();
    }
  }

  @action
  selectLocation(index) {
    this.selectedLocationIndex = index;
    this.showLocationDropdown = false;
    this.cleanupClickOutside();
  }

  @action
  hideDropdown() {
    this.showLocationDropdown = false;
    this.cleanupClickOutside();
  }

  setupClickOutside() {
    this.clickOutsideHandler = (e) => {
      if (!e.target.closest(".vzekc-map-location-selector")) {
        this.hideDropdown();
      }
    };
    setTimeout(() => {
      document.addEventListener("click", this.clickOutsideHandler);
    }, 0);
  }

  cleanupClickOutside() {
    if (this.clickOutsideHandler) {
      document.removeEventListener("click", this.clickOutsideHandler);
      this.clickOutsideHandler = null;
    }
  }

  willDestroy() {
    super.willDestroy();
    this.cleanupClickOutside();
  }

  <template>
    {{#if this.hasLocations}}
      <div class="vzekc-map-profile-links">
        {{#if this.hasMultipleLocations}}
          <div class="vzekc-map-location-selector">
            <button
              type="button"
              class="vzekc-map-location-toggle"
              {{on "click" this.toggleLocationDropdown}}
            >
              {{icon "map-marker-alt"}}
              <span class="location-label">{{this.locationLabel}}</span>
              {{icon "chevron-down" class="chevron"}}
            </button>
            {{#if this.showLocationDropdown}}
              <div class="vzekc-map-location-dropdown">
                {{#each this.locations as |loc index|}}
                  <button
                    type="button"
                    class="vzekc-map-location-option {{if (eq index this.selectedLocationIndex) 'selected'}}"
                    {{on "click" (fn this.selectLocation index)}}
                  >
                    {{#if loc.name}}
                      {{loc.name}}
                    {{else}}
                      {{loc.lat}}, {{loc.lng}}
                    {{/if}}
                  </button>
                {{/each}}
              </div>
            {{/if}}
          </div>
        {{/if}}
        <div class="vzekc-map-links">
          <a
            href={{this.googleMapsUrl this.currentLocation}}
            target="_blank"
            rel="noopener noreferrer"
            title={{i18n "vzekc_map.profile_links.google_maps"}}
            class="vzekc-map-link"
          >
            {{icon "external-link-alt"}}
            {{i18n "vzekc_map.profile_links.google_maps"}}
          </a>
          <a
            href={{this.appleMapsUrl this.currentLocation}}
            target="_blank"
            rel="noopener noreferrer"
            title={{i18n "vzekc_map.profile_links.apple_maps"}}
            class="vzekc-map-link"
          >
            {{icon "external-link-alt"}}
            {{i18n "vzekc_map.profile_links.apple_maps"}}
          </a>
          <a
            href={{this.openStreetMapUrl this.currentLocation}}
            target="_blank"
            rel="noopener noreferrer"
            title={{i18n "vzekc_map.profile_links.openstreetmap"}}
            class="vzekc-map-link"
          >
            {{icon "external-link-alt"}}
            {{i18n "vzekc_map.profile_links.openstreetmap"}}
          </a>
        </div>
      </div>
    {{/if}}
  </template>
}
