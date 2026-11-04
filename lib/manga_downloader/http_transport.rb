# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module MangaDownloader
  # Small Net::HTTP wrapper: one connection per request, browser-like
  # User-Agent, sensible timeouts, and streaming so images never sit in memory.
  #
  # `#stream` raises on network/HTTP-level transport errors; callers decide how
  # (and how often) to retry. `#get_json` retries on its own because API calls
  # are not written to disk and are cheap to repeat.
  class HttpTransport
    USER_AGENT = 'Mozilla/5.0'

    def initialize(config, reporter: nil, sleeper: ->(seconds) { sleep(seconds) })
      @config = config
      @reporter = reporter
      @sleeper = sleeper
    end

    def get_json(url)
      attempt = 0

      begin
        attempt += 1
        body = +''
        status = stream(url) { |chunk| body << chunk }
        return nil unless success?(status)

        JSON.parse(body)
      rescue JSON::ParserError => e
        @reporter&.warn("  Invalid JSON from #{url}: #{e.message}")
        nil
      rescue StandardError => e
        if attempt > @config.http_retries
          @reporter&.warn("  Error fetching #{url}: #{e.message}")
          return nil
        end

        @sleeper.call(@config.http_retry_delay)
        retry
      end
    end

    # Streams a GET response body to the block and returns the HTTP status.
    # Raises on connection failures so the caller can retry/clean up.
    def stream(url, &block)
      uri = URI.parse(url)

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: @config.http_open_timeout,
        read_timeout: @config.http_read_timeout
      ) do |http|
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = USER_AGENT

        status = nil
        http.request(request) do |response|
          status = response.code.to_i
          response.read_body(&block) if response.is_a?(Net::HTTPSuccess)
        end
        status
      end
    end

    def success?(status)
      !status.nil? && (200..299).cover?(status)
    end
  end
end
