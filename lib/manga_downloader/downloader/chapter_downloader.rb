# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'uri'
require_relative '../errors'
require_relative '../memory'
require_relative '../naming'
require_relative '../scraping/browser_session'
require_relative '../scraping/html'
require_relative 'chapter_marker'
require_relative 'image_fetcher'

module MangaDownloader
  module Downloader
    # Downloads every chapter of one manga, oldest first. A fresh browser is
    # used per chapter because Chromium and Ferrum keep growing while a page is
    # alive; quitting it guarantees the memory is released.
    class ChapterDownloader
      Summary = Data.define(:completed, :skipped, :partial, :failed) do
        def self.empty = new(completed: 0, skipped: 0, partial: 0, failed: 0)
        def processed = completed + partial + failed
      end

      def initialize(config:, manga_name:, chapters:, reporter:,
                     fetcher: nil, browser_factory: nil,
                     sleeper: ->(seconds) { sleep(seconds) })
        @config = config
        @manga_name = manga_name
        @chapters = chapters
        @reporter = reporter
        @fetcher = fetcher || ImageFetcher.new(
          config: config, reporter: reporter, manga_name: manga_name
        )
        @browser_factory = browser_factory || -> { Scraping::BrowserSession.build(config) }
        @sleeper = sleeper
      end

      def call(limit: nil, skip_existing: false)
        ordered = @chapters.ordered_ascending
        return empty_summary('Nothing to download.') if ordered.empty?

        manga_root = File.join(@config.mangas_dir, Naming.path_segment(@manga_name))
        FileUtils.mkdir_p(manga_root)
        summary = Summary.empty

        ordered.each_with_index do |chapter, index|
          break if limit_reached?(limit, summary)

          summary, status = download_chapter(chapter, manga_root, summary, skip_existing: skip_existing)
          break if limit_reached?(limit, summary)
          next if status == :skipped || index >= ordered.size - 1

          pause_before_next_chapter
        end

        @reporter.info("All done at #{Time.now}")
        summary
      end

      private

      def empty_summary(message)
        @reporter.info(message)
        Summary.empty
      end

      def limit_reached?(limit, summary)
        !limit.nil? && summary.completed >= limit
      end

      def pause_before_next_chapter
        delay = @config.chapter_delay_seconds
        @reporter.info("  Waiting #{delay}s before next chapter...")
        @sleeper.call(delay)
      end

      # Returns [updated_summary, status]. Status is used by the caller to avoid
      # pacing between chapters that were skipped or never downloaded.
      def download_chapter(chapter, manga_root, summary, skip_existing:)
        title = chapter.title || chapter.id
        directory = File.join(manga_root, Naming.path_segment(title))

        if skip_existing && ChapterMarker.complete?(directory)
          return [summary.with(skipped: summary.skipped + 1), :skipped]
        end

        unless chapter.href
          @reporter.error('chapter has no href, skipping', manga: @manga_name, chapter: title)
          return [summary.with(failed: summary.failed + 1), :failed]
        end

        status = fetch_chapter(chapter, title, directory)
        [summary.with(**{ status => summary.public_send(status) + 1 }), status]
      end

      def fetch_chapter(chapter, title, directory)
        ChapterMarker.mark_partial(directory)
        @reporter.info("Loading #{title}")
        browser = nil
        page = nil

        begin
          browser = @browser_factory.call
          page = browser.create_page
          page.go_to(absolute_url(chapter.href))
          page.network.wait_for_idle
          sleep(@config.navigation_delay)

          image_urls = Scraping::Html.page_image_urls(page.body)
          return chapter_without_images(title) if image_urls.empty?

          @reporter.progress("  Found #{image_urls.size} pages, downloading...\t")
          complete = download_images(image_urls, directory, title)

          if complete
            ChapterMarker.mark_complete(directory)
            @reporter.info("  Done: #{image_urls.size} images saved")
            :completed
          else
            @reporter.warn('  Some pages failed; chapter will be retried next run')
            :partial
          end
        rescue StandardError => e
          @reporter.error("chapter error: #{e.class}: #{e.message}", manga: @manga_name, chapter: title)
          :failed
        ensure
          clear_page(page)
          Scraping::BrowserSession.quit(browser)
          Memory.release
        end
      end

      def chapter_without_images(title)
        @reporter.error('no images found, skipping chapter', manga: @manga_name, chapter: title)
        :failed
      end

      def absolute_url(href)
        href.start_with?('http') ? href : "#{@config.base_url}#{href}"
      end

      # Fixed-size worker pool: image_threads is clamped to 1..10 by Config,
      # so a chapter never downloads more than 10 images at a time.
      def download_images(image_urls, directory, title)
        queue = Queue.new
        image_urls.each_with_index { |url, index| queue << [url, index] }
        queue.close

        results = Array.new(image_urls.size, false)
        worker_count = [@config.image_threads, image_urls.size].min

        workers = Array.new(worker_count) do
          Thread.new do
            while (item = queue.pop)
              url, index = item
              results[index] = @fetcher.fetch(url, destination(directory, index, url), chapter: title)
            end
          end
        end

        workers.each(&:join)
        results.all?
      end

      def destination(directory, index, url)
        extension = File.extname(URI.parse(url).path)
        extension = '.webp' if extension.empty?
        File.join(directory, format('%<index>03d%<extension>s', index: index, extension: extension))
      end

      def clear_page(page)
        page&.network&.clear(:traffic)
      rescue StandardError
        nil
      end
    end
  end
end
