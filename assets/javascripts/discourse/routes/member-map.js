import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseRoute from "discourse/routes/discourse";

export default class MemberMapRoute extends DiscourseRoute {
  model() {
    return ajax("/vzekc-map/locations.json", {
      type: "GET",
    }).catch(popupAjaxError);
  }
}
