import { i18n } from "discourse-i18n";
import MemberMap from "../components/member-map";

<template>
  <div class="member-map-page">
    <div class="member-map-header">
      <h1>{{i18n "vzekc_map.title"}}</h1>
    </div>
    <MemberMap @locations={{@model.locations}} @poi={{@controller.poi}} />
    <div class="member-map-help">
      <h3>{{i18n "vzekc_map.help.title"}}</h3>
      <ul>
        <li>{{i18n "vzekc_map.help.view"}}</li>
        <li>{{i18n "vzekc_map.help.search"}}</li>
        <li>{{i18n "vzekc_map.help.add"}}</li>
        <li>{{i18n "vzekc_map.help.delete"}}</li>
        <li>{{i18n "vzekc_map.help.home"}}</li>
      </ul>
    </div>
  </div>
</template>
