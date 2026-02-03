# frozen_string_literal: true

module Jobs
  class VzekcMapWoltlabSync < ::Jobs::Base
    sidekiq_options retry: 3

    def execute(args)
      username = args[:username]
      geoinformation = args[:geoinformation]

      return if username.blank?

      url = SiteSetting.vzekc_map_woltlab_sync_url
      secret = SiteSetting.vzekc_map_woltlab_sync_secret

      return if url.blank? || secret.blank?

      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["X-Sync-Secret"] = secret

      request.body = {
        username: username,
        geoinformation: geoinformation
      }.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn(
          "VzekcMap WoltLab sync failed for #{username}: " \
          "HTTP #{response.code} - #{response.body}"
        )
      end
    rescue StandardError => e
      Rails.logger.error("VzekcMap WoltLab sync error for #{username}: #{e.message}")
      raise # Re-raise to trigger Sidekiq retry
    end
  end
end
