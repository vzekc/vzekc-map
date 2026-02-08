import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { eq } from "truth-helpers";
import { autoUpdatingRelativeAge } from "discourse/lib/formatter";
import { htmlSafe } from "@ember/template";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

export default class MapActivityLog extends Component {
  @tracked filter = "all"; // "all", "locations", "pois"

  get allChanges() {
    const userChanges = (this.args.userChanges || []).map((entry) => ({
      ...entry,
      entryType: "location",
    }));

    const poiChanges = (this.args.poiChanges || []).map((entry) => ({
      ...entry,
      entryType: "poi",
    }));

    // Merge and sort by timestamp (newest first)
    const all = [...userChanges, ...poiChanges].sort(
      (a, b) => new Date(b.timestamp) - new Date(a.timestamp)
    );

    return all;
  }

  get filteredChanges() {
    let changes = this.allChanges;

    if (this.filter === "locations") {
      changes = changes.filter((e) => e.entryType === "location");
    } else if (this.filter === "pois") {
      changes = changes.filter((e) => e.entryType === "poi");
    }

    // Always return 20 entries
    return changes.slice(0, 20);
  }

  get lastVisit() {
    return this.args.lastVisit;
  }

  isNewEntry = (timestamp) => {
    if (!this.lastVisit) {
      return false;
    }
    return new Date(timestamp) > new Date(this.lastVisit);
  };

  formatAge(timestamp) {
    const date = new Date(timestamp);
    return htmlSafe(autoUpdatingRelativeAge(date, { format: "tiny" }));
  }

  getLocationHash(location) {
    if (!location) {
      return null;
    }
    const zoom = location.zoom || 15;
    return `#map=${zoom}/${location.lat.toFixed(5)}/${location.lng.toFixed(5)}`;
  }

  @action
  navigateToLocation(location, event) {
    event.preventDefault();
    const hash = this.getLocationHash(location);
    if (hash) {
      window.location.href = getURL(`/member-map${hash}`);
    }
  }

  @action
  setFilter(filterType) {
    this.filter = filterType;
  }

  getUserUrl(username) {
    return getURL(`/u/${username}`);
  }

  getTopicUrl(slug, topicId) {
    return getURL(`/t/${slug}/${topicId}`);
  }

  <template>
    <div class="member-map-activity">
      <div class="activity-header">
        <h3>{{i18n "vzekc_map.activity.title"}}</h3>
        <div class="activity-filters">
          <button
            type="button"
            class="activity-filter-btn {{if (eq this.filter 'all') 'active'}}"
            {{on "click" (fn this.setFilter "all")}}
          >
            {{i18n "vzekc_map.activity.filter_all"}}
          </button>
          <button
            type="button"
            class="activity-filter-btn {{if (eq this.filter 'locations') 'active'}}"
            {{on "click" (fn this.setFilter "locations")}}
          >
            {{i18n "vzekc_map.activity.filter_locations"}}
          </button>
          <button
            type="button"
            class="activity-filter-btn {{if (eq this.filter 'pois') 'active'}}"
            {{on "click" (fn this.setFilter "pois")}}
          >
            {{i18n "vzekc_map.activity.filter_pois"}}
          </button>
        </div>
      </div>

      {{#if this.filteredChanges.length}}
        <ul class="activity-list">
          {{#each this.filteredChanges as |entry|}}
            <li class="activity-entry {{if (this.isNewEntry entry.timestamp) 'new'}}">
              <span class="activity-time">{{this.formatAge entry.timestamp}}</span>
              <span class="activity-content">
                {{#if (eq entry.entryType "location")}}
                  <a href={{this.getUserUrl entry.user.username}} class="activity-user">@{{entry.user.username}}</a>
                  {{#if (eq entry.type "added")}}
                    {{i18n "vzekc_map.activity.location_added_prefix"}}
                    {{#if entry.location}}
                      <a href="#" class="activity-location" {{on "click" (fn this.navigateToLocation entry.location)}}>{{i18n "vzekc_map.activity.home_location"}}</a>
                    {{else}}
                      {{i18n "vzekc_map.activity.home_location"}}
                    {{/if}}
                    {{i18n "vzekc_map.activity.location_added_suffix"}}
                  {{else}}
                    {{i18n "vzekc_map.activity.location_updated_prefix"}}
                    {{#if entry.location}}
                      <a href="#" class="activity-location" {{on "click" (fn this.navigateToLocation entry.location)}}>{{i18n "vzekc_map.activity.home_location"}}</a>
                    {{else}}
                      {{i18n "vzekc_map.activity.home_location"}}
                    {{/if}}
                    {{i18n "vzekc_map.activity.location_updated_suffix"}}
                  {{/if}}
                {{else}}
                  <a href={{this.getUserUrl entry.user.username}} class="activity-user">@{{entry.user.username}}</a>
                  {{#if (eq entry.type "added")}}
                    {{i18n "vzekc_map.activity.poi_added_prefix"}}
                    <a href={{this.getTopicUrl entry.slug entry.topic_id}} class="activity-poi">{{entry.title}}</a>
                    {{i18n "vzekc_map.activity.poi_added_suffix"}}
                  {{else}}
                    {{i18n "vzekc_map.activity.poi_updated_prefix"}}
                    <a href={{this.getTopicUrl entry.slug entry.topic_id}} class="activity-poi">{{entry.title}}</a>
                    {{i18n "vzekc_map.activity.poi_updated_suffix"}}
                  {{/if}}
                {{/if}}
              </span>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="activity-empty">{{i18n "vzekc_map.activity.no_recent_changes"}}</p>
      {{/if}}
    </div>
  </template>
}
