import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

export default {
  name: "map-sidebar-section",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const currentUser = container.lookup("service:current-user");

    if (!siteSettings.vzekc_map_enabled) {
      return;
    }

    // Check if current user is a member of the allowed group
    const membersGroupName = siteSettings.vzekc_map_members_group_name;
    const isMember =
      currentUser &&
      membersGroupName &&
      currentUser.groups?.some((g) => g.name === membersGroupName);

    if (!isMember) {
      return;
    }

    withPluginApi((api) => {
      api.addSidebarSection(
        (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
          const MemberMapLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "member-map";
            }

            get route() {
              return "memberMap";
            }

            get text() {
              return i18n("vzekc_map.nav.member_map");
            }

            get title() {
              return i18n("vzekc_map.nav.member_map");
            }

            get prefixType() {
              return "icon";
            }

            get prefixValue() {
              return "map";
            }
          };

          return class MapSection extends BaseCustomSidebarSection {
            get name() {
              return "vzekc-map";
            }

            get text() {
              return i18n("vzekc_map.nav.section_title");
            }

            get collapsedByDefault() {
              return false;
            }

            get links() {
              return [new MemberMapLink()];
            }
          };
        }
      );
    });
  },
};
