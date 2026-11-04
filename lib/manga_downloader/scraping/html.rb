# frozen_string_literal: true

require 'json'
require 'nokogiri'

module MangaDownloader
  module Scraping
    # Pure HTML → data extraction, kept free of browser state so it can be
    # unit-tested with fixture HTML.
    module Html
      module_function

      # Chapter links are rendered as `<a href="/read/<manga>/<chapter>">`,
      # sometimes twice per row (with and without a title).
      def chapter_links(html)
        found = {}

        Nokogiri::HTML(html).css('a[href*="/read/"]').each do |anchor|
          href = anchor['href']
          id = href[%r{/read/[^/]+/([^/"]+)}, 1]
          next unless id

          title = anchor.at_css('span.truncate')&.text&.strip

          # "Start reading" points at the first chapter and would shadow its
          # real title, so ignore it.
          next if title == 'Start reading'

          existing = found[id]
          found[id] = { 'title' => title, 'href' => href } if existing.nil? || existing['title'].nil?
        end

        found
      end

      # Merges newly scraped chapters without downgrading a known title to nil.
      def merge_chapters!(seen, new_entries)
        new_entries.each do |id, info|
          existing = seen[id]
          seen[id] = info if existing.nil? || (existing['title'].nil? && info['title'])
        end
        seen
      end

      def manga_page_data(html)
        script = Nokogiri::HTML(html).xpath('//script[contains(text(), "window.mangaPage =")]').first
        return nil unless script

        json = script.text[/window\.mangaPage = (\{.*\});\s*\z/m, 1]
        return nil unless json

        JSON.parse(json)['mangaPage']
      rescue JSON::ParserError
        nil
      end

      def page_title(html)
        Nokogiri::HTML(html).at_css('title')&.text&.strip
      end

      def page_image_urls(html)
        Nokogiri::HTML(html).css('div[data-reader-page] img').filter_map { |img| img['src'] }
      end

      def search_results(html)
        doc = Nokogiri::HTML(html)
        names = doc.css('div.text-xs.line-clamp-3').map { |node| node.text.strip }
        hrefs = doc.css('a[href^="/manga/"]').map { |anchor| anchor['href'] }
        names.zip(hrefs).filter_map do |name, href|
          next if name.nil? || name.empty? || href.nil?

          { name: name, href: href }
        end
      end
    end
  end
end
