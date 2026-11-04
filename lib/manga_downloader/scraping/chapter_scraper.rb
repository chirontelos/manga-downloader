# frozen_string_literal: true

require_relative '../domain/chapter_list'
require_relative '../domain/source_selection'
require_relative '../labels'
require_relative '../manga_id'
require_relative 'html'

module MangaDownloader
  module Scraping
    # Drives the virtualized chapter list on a manga page. The page scrolling
    # and settling rules live here; ordering and source policy are delegated to
    # the domain objects.
    class ChapterScraper
      def initialize(page:, config:, api:, metadata:, reporter:, ui: nil)
        @page = page
        @config = config
        @api = api
        @metadata = metadata
        @reporter = reporter
        @ui = ui
        @page_data = nil
      end

      def get_chapter_list(manga_href)
        navigate(manga_href)
        record_metadata(manga_href)

        seen = scroll_through_chapters
        chapters = Domain::ChapterList.from_local_hash(seen).ordered_descending
        select_sources(manga_href, chapters)
      end

      private

      def navigate(manga_href)
        @page.go_to("#{@config.base_url}#{manga_href}?filter=all")
        wait_for_idle
        sleep(@config.navigation_delay)
      end

      def wait_for_idle
        @page.network.wait_for_idle
      rescue Ferrum::Error
        nil
      end

      def record_metadata(manga_href)
        @page_data = Html.manga_page_data(@page.body)
        return unless @page_data && @page_data['status']

        id = @page_data['id'] || MangaId.from_href(manga_href)
        return unless id

        @metadata.record("/manga/#{id}", status: @page_data['status'])
      end

      def scroll_through_chapters
        scroll_to_heading
        seen = {}
        stale_iterations = 0
        iteration = 0

        loop do
          iteration += 1
          merge_and_scroll(seen)
          previous_count = seen.size

          merge(seen)
          at_bottom = at_bottom?

          stale_iterations = seen.size == previous_count ? stale_iterations + 1 : 0

          break if stale_iterations >= @config.stale_iterations_before_stop && at_bottom
          break if iteration >= @config.max_scroll_iterations
        end

        settle_at_bottom(seen)
        seen
      end

      def scroll_to_heading
        @page.execute(<<~JS)
          const headings = Array.from(document.querySelectorAll('h2'));
          const chaptersHeading = headings.find(h => h.textContent.trim() === 'Chapters');
          if (chaptersHeading) {
            chaptersHeading.scrollIntoView({ block: 'start' });
          }
        JS
        wait_for_idle
        sleep(@config.scroll_delay)
      end

      def merge_and_scroll(seen)
        merge(seen)
        @page.execute("window.scrollBy(0, #{@config.scroll_step})")
        wait_for_idle
        sleep(@config.scroll_delay)
      end

      def merge(seen)
        Html.merge_chapters!(seen, Html.chapter_links(@page.body))
      end

      def at_bottom?
        @page.evaluate('window.innerHeight + window.scrollY >= document.body.scrollHeight - 10')
      end

      # The last rows (e.g. "Prologue 1") often render late once the bottom is
      # reached. Keep nudging the viewport until nothing new shows up.
      def settle_at_bottom(seen)
        quiet = 0

        @config.max_settle_attempts.times do
          before = seen.size

          @page.execute("window.scrollBy(0, -#{@config.scroll_up_step})")
          sleep(@config.navigation_delay)
          merge(seen)

          @page.execute('window.scrollTo(0, document.body.scrollHeight)')
          wait_for_idle
          sleep(@config.bottom_delay)
          merge(seen)

          quiet = seen.size == before ? quiet + 1 : 0

          break if quiet >= @config.quiet_iterations_before_stop
        end
      end

      def select_sources(manga_href, chapters)
        id = MangaId.from_href(manga_href) || MangaId.from_chapter_list(chapters)
        return chapters unless id

        page_data = @page_data || @api.manga_page(id)
        return chapters unless multiple_sources?(page_data)

        all_chapters = @api.all_chapters(id)
        return chapters unless usable_chapters?(all_chapters)
        return chapters unless multiple_sources_in?(all_chapters)

        choose_and_merge(id, page_data, all_chapters)
      end

      def multiple_sources?(page_data)
        page_data && Array(page_data['scanlators']).size >= 2
      end

      def usable_chapters?(all_chapters)
        all_chapters && !all_chapters.empty?
      end

      def multiple_sources_in?(all_chapters)
        all_chapters.group_by { |chapter| chapter['scanlationMangaId'] }.size >= 2
      end

      def choose_and_merge(id, page_data, all_chapters)
        sources = Domain::SourceSelection.build(page_data: page_data, all_chapters: all_chapters, manga_id: id)
        chosen = Domain::SourceSelection.choose(sources, ui: @ui, reporter: @reporter)
        merged, used_sources = Domain::SourceSelection.merge(chosen)

        if used_sources.size > 1
          names = used_sources.map(&:name).join(', ')
          @reporter.info("No single source covers the entire manga. Using #{names}.")
        end

        @metadata.record("/manga/#{id}", source_ids: used_sources.map(&:id))
        merged
      end
    end
  end
end
