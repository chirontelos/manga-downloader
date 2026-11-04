# frozen_string_literal: true

require 'uri'
require_relative '../http_transport'

module MangaDownloader
  module Api
    # The site's JSON API. Mirrors the two endpoints the scraper relies on.
    class Client
      def initialize(config, http: nil, reporter: nil)
        @config = config
        @http = http || HttpTransport.new(config, reporter: reporter)
        @reporter = reporter
      end

      def manga_page(id)
        get_json('manga/page', id: id)&.dig('mangaPage')
      end

      def all_chapters(id)
        get_json('manga/allChapters', mangaId: id)&.dig('chapters')
      end

      def get_json(path, **params)
        query = URI.encode_www_form(params)
        @http.get_json("#{@config.api_base}/#{path}?#{query}")
      end
    end
  end
end
