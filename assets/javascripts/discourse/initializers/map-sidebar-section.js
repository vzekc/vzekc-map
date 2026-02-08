import { ajax } from "discourse/lib/ajax";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

// Global state for new content indicator
const state = {
  hasNewContent: false,
};

export default {
  name: "map-sidebar-section",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const currentUser = container.lookup("service:current-user");
    const messageBus = container.lookup("service:message-bus");

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

    // Check for new content on load
    ajax("/vzekc-map/has-new-content.json")
      .then((result) => {
        state.hasNewContent = result.has_new;
        // Manually add class since sidebar may already be rendered
        if (result.has_new) {
          document
            .querySelector('.sidebar-section-link[data-link-name="member-map"]')
            ?.classList.add("has-new-content");
        }
      })
      .catch(() => {});

    // Subscribe to MessageBus for real-time updates
    messageBus.subscribe("/vzekc-map/new-content", (data) => {
      if (data.has_new && !window.location.pathname.startsWith("/member-map")) {
        state.hasNewContent = true;
        document
          .querySelector('.sidebar-section-link[data-link-name="member-map"]')
          ?.classList.add("has-new-content");
      }
    });

    withPluginApi((api) => {
      // Clear indicator when navigating to member-map
      api.onPageChange((url) => {
        if (url.startsWith("/member-map")) {
          state.hasNewContent = false;
          // Manually remove the class since sidebar doesn't re-render
          document
            .querySelector('.sidebar-section-link[data-link-name="member-map"]')
            ?.classList.remove("has-new-content");
        }
      });

      api.addSidebarSection(
        (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
          const MemberMapLink = class extends BaseCustomSidebarSectionLink {
            get name() {
              return "member-map";
            }

            get route() {
              return "memberMap";
            }

            get href() {
              return "/member-map";
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

            get classNames() {
              return state.hasNewContent ? "has-new-content" : "";
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
