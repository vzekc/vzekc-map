import { i18n } from "discourse-i18n";
import MemberMap from "../components/member-map";

<template>
  <div class="member-map-page">
    <div class="member-map-header">
      <h1>{{i18n "vzekc_map.title"}}</h1>
    </div>
    <MemberMap @locations={{@model.locations}} />
  </div>
</template>
