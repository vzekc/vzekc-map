# frozen_string_literal: true

module VzekcMap
  # Syncs location changes back to WoltLab via HTTP API
  class WoltlabSync
    def self.sync_location(user)
      return unless enabled?

      geoinformation = user.custom_fields["Geoinformation"] || ""

      Jobs.enqueue(
        :vzekc_map_woltlab_sync,
        username: user.username,
        geoinformation: geoinformation
      )
    end

    def self.enabled?
      SiteSetting.vzekc_map_woltlab_sync_enabled &&
        SiteSetting.vzekc_map_woltlab_sync_url.present? &&
        SiteSetting.vzekc_map_woltlab_sync_secret.present?
    end
  end
end
