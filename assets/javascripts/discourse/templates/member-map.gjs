import { i18n } from "discourse-i18n";
import MemberMap from "../components/member-map";
import MapActivityLog from "../components/map-activity-log";

<template>
  <div class="member-map-page">
    <div class="member-map-header">
      <h1>{{i18n "vzekc_map.title"}}</h1>
    </div>
    <MemberMap @locations={{@model.locations}} @poi={{@controller.poi}} />
    <MapActivityLog
      @userChanges={{@model.user_changes}}
      @poiChanges={{@model.poi_changes}}
      @lastVisit={{@model.last_visit}}
    />
  </div>
</template>
