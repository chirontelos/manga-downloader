# frozen_string_literal: true

require 'uri'
require_relative '../manga_id'
require_relative 'html'
require_relative 'chapter_scraper'

module MangaDownloader
  module Scraping
    # Finds mangas by name or URL. Returns data only; choosing a result is the
    # CLI's job, which keeps this class free of interactive prompts.
    class MangaSearch
      attr_reader :chapter_scraper

      def initialize(page:, config:, api:, metadata:, reporter:, ui: nil)
        @page = page
        @config = config
        @reporter = reporter
        @chapter_scraper = ChapterScraper.new(
          page: page, config: config, api: api, metadata: metadata, reporter: reporter, ui: ui
        )
      end

      def search(name)
        navigate("/explore?search=#{URI.encode_www_form_component(name)}")
        results = Html.search_results(@page.body)
        return [] if results.empty?

        disambiguate_duplicate_names(results)
        results
      end

      # Resolves a full manga URL into {name:, href:, chapters:}. Returns nil
      # for non-URL input or pages that didn't load, so callers can fall back
      # to a name search.
      def resolve_link(input)
        id = MangaId.from_input(input)
        return nil unless id

        href = "/manga/#{id}"
        navigate(href)

        title = Html.page_title(@page.body)
        return nil if title.nil? || title.empty? || title == 'Atsumaru'

        chapters = @chapter_scraper.get_chapter_list(href)
        return nil if chapters.empty?

        { name: title, href: href, chapters: chapters }
      rescue Ferrum::Error => e
        @reporter.warn("  Could not open #{input}: #{e.message}")
        nil
      end

      private

      def navigate(path)
        @page.go_to("#{@config.base_url}#{path}")
        @page.network.wait_for_idle
        sleep(@config.navigation_delay)
      end

      # Mangas can share the exact same name on the site. Append the chapter
      # count so they don't overwrite each other's file or download folder.
      def disambiguate_duplicate_names(results)
        results.group_by { |result| result[:name] }.each_value do |group|
          next if group.size < 2

          group.each do |manga|
            chapters = @chapter_scraper.get_chapter_list(manga[:href])
            manga[:chapters] = chapters
            manga[:name] = "#{manga[:name]} #{chapters.size}"
          end
        end
      end
    end
  end
end
