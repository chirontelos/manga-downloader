# frozen_string_literal: true

require_relative 'domain/chapter_list'
require_relative 'domain/chapter_selection'
require_relative 'downloader/chapter_downloader'
require_relative 'labels'
require_relative 'library'
require_relative 'scraping/browser_session'
require_relative 'scraping/manga_search'
require_relative 'updates/checker'

module MangaDownloader
  # The interactive menu. Every prompt and every "what should we do with this
  # result" decision lives here, so the scraping/domain objects stay passive.
  class InteractiveSession
    MENU = <<~TEXT

      ===== Manga Downloader =====
      [a] manga name or link to download now
      [b] add manga to list
      [c] list mangas and download
      [d] check for updates
      [q] quit
    TEXT

    def initialize(config:, store:, metadata:, api:, ui:, reporter:)
      @config = config
      @store = store
      @metadata = metadata
      @api = api
      @ui = ui
      @reporter = reporter
      @library = Library.new(config: config, store: store)
      @checker = Updates::Checker.new(
        config: config, store: store, metadata: metadata, api: api, reporter: reporter
      )
    end

    def run
      loop do
        @reporter.info(MENU)

        case prompt('Choose an option: ')&.downcase
        when 'a' then download_now
        when 'b' then add_manga
        when 'c' then list_library
        when 'd' then check_for_updates
        when 'q', nil then break
        else @reporter.info('Invalid option.')
        end
      end
    end

    private

    def download_now
      input = prompt('Enter manga name or link: ')
      return if input.nil? || input.empty?

      if @store.exist?(input)
        start_download(input, @store.load(input))
        return
      end

      with_search do |search|
        linked = search.resolve_link(input)

        if linked
          save_result(linked, search: search, overwrite: false)
          start_download(linked[:name], @store.load(linked[:name]))
          next
        end

        results = search.search(input)
        if results.empty?
          @reporter.info('Manga not found.')
          next
        end

        selected = choose_results(
          results, heading: "\nMangas found:",
                   question: "\nSelect manga(s) to download now, separated by commas (or blank to skip): "
        )
        next unless selected

        selected.each_with_index do |result, index|
          save_result(result, search: search, overwrite: true)
          start_download(result[:name], @store.load(result[:name]))
          pause_between_mangas if index < selected.size - 1
        end
      end
    end

    def add_manga
      input = prompt('Enter manga name(s) or link(s), separated by commas if multiple: ')
      names = input.to_s.split(',').map(&:strip).reject(&:empty?)
      return if names.empty?

      with_search do |search|
        names.each_with_index do |name, index|
          add_manga_name(search, name)
          pause_between_mangas if index < names.size - 1
        end
      end
    end

    def add_manga_name(search, name)
      @reporter.info("Searching for \"#{name}\"...")
      linked = search.resolve_link(name)
      return save_search_result(linked, search) if linked

      found = search.search(name)
      selected = choose_results(found, heading: "Mangas found for \"#{name}\":",
                                       question: 'Enter letter(s), separated by commas (or blank to skip): ')
      if selected.nil?
        @reporter.info("  Not found: #{name}") if found.empty?
        return
      end

      selected.each { |result| save_search_result(result, search) }
    end

    def save_search_result(result, search)
      chapters = result[:chapters] || search.chapter_scraper.get_chapter_list(result[:href])
      @store.save(result[:name], chapters)
      @reporter.info("  Saved #{chapters.size} chapters to #{@store.path_for(result[:name])}")
    end

    def list_library
      downloaded, pending = @library.list_mangas

      if downloaded.empty? && pending.empty?
        @reporter.info('No saved manga lists found.')
        return
      end

      display_library(downloaded, pending)
      mapping = pending_mapping(pending)

      input = prompt("\nDownload one now? Enter letter (or blank to skip): ")&.downcase
      return if input.nil? || input.empty?

      name = mapping[input]
      unless name
        @reporter.info("Invalid option: #{input}")
        return
      end

      start_download(name, @store.load(name))
    end

    def display_library(downloaded, pending)
      @reporter.info("\nDownloaded mangas:")
      if downloaded.empty?
        @reporter.info('  (none)')
      else
        downloaded.each { |name| @reporter.info("  - #{name}") }
      end

      @reporter.info("\nAdded but not downloaded yet:")
      @reporter.info('  (none)') if pending.empty?
    end

    def pending_mapping(pending)
      labels = Labels.for(pending.size)
      pending.each_with_index.with_object({}) do |(name, index), mapping|
        letter = labels[index]
        mapping[letter] = name if letter
        @reporter.info("  [#{letter || '?'}] #{name}")
      end
    end

    def check_for_updates
      @reporter.info('Checking for updates...')
      updates = @checker.call

      if updates.empty?
        @reporter.info('No updates found.')
        return
      end

      mapping = display_updates(updates)
      input = prompt("\nDownload new chapter(s)? Enter letter(s), separated by commas (or blank to skip): ")
      return if input.nil? || input.empty?

      selected = input.split(',').map(&:strip).filter_map { |letter| mapping[letter] }
      if selected.empty?
        @reporter.info('No matching selection.')
        return
      end

      download_updates(selected)
    end

    def display_updates(updates)
      labels = Labels.for(updates.size)
      mapping = {}

      @reporter.info("\nMangas with new chapters:")
      updates.each_with_index do |update, index|
        letter = labels[index]
        next unless letter

        mapping[letter] = update
        @reporter.info("[#{letter}] #{update.name} (+#{update.new_chapters.size} new chapter(s), #{update.status})")
      end

      mapping
    end

    def download_updates(selected)
      selected.each_with_index do |update, index|
        additions = @checker.apply(update)
        next if additions.empty?

        chapters = Domain::ChapterList.from_local_hash(additions)
        Downloader::ChapterDownloader.new(
          config: @config, manga_name: update.name, chapters: chapters, reporter: @reporter
        ).call

        pause_between_mangas if index < selected.size - 1
      end
    end

    def choose_results(results, heading:, question:)
      return nil if results.empty?
      return [results.first] if results.size == 1

      labels = Labels.for(results.size)
      @reporter.info(heading)
      results.each_with_index do |result, index|
        @reporter.info("[#{labels[index]}] #{result[:name]}")
      end

      input = prompt(question)
      return nil if input.nil? || input.empty?

      selected = parse_selection(input, labels).filter_map { |index| results[index] }
      @reporter.info('Invalid selection.') if selected.empty?
      selected.empty? ? nil : selected
    end

    # Accepts "a, b" or "a b".
    def parse_selection(input, labels)
      input.downcase.split(/[,\s]+/).uniq.filter_map { |token| labels.index(token) }
    end

    def save_result(result, search:, overwrite:)
      chapters = result[:chapters] || search.chapter_scraper.get_chapter_list(result[:href])

      if overwrite || !@store.exist?(result[:name])
        @store.save(result[:name], chapters)
        @reporter.info("Saved #{chapters.size} chapters to #{@store.path_for(result[:name])}")
      end

      { name: result[:name], chapters: chapters }
    end

    def start_download(name, chapters)
      range = prompt('Enter chapter(s) to download (e.g. "100-105", "100", "100,135,151", or "all"): ')
      return if range.nil? || range.empty?

      selected = if range.downcase == 'all'
                   chapters
                 else
                   Domain::ChapterSelection.parse(range, chapters)
                 end

      if selected.empty?
        @reporter.info('No matching chapters found.')
        return
      end

      Downloader::ChapterDownloader.new(
        config: @config, manga_name: name, chapters: selected, reporter: @reporter
      ).call
    end

    def with_search
      Scraping::BrowserSession.open(@config) do |page|
        search = Scraping::MangaSearch.new(
          page: page, config: @config, api: @api, metadata: @metadata,
          reporter: @reporter, ui: @ui
        )
        yield search
      end
    end

    def pause_between_mangas
      delay = @config.manga_delay_seconds
      @reporter.info("  Waiting #{delay}s before next manga...")
      sleep(delay)
    end

    def prompt(message)
      @ui.ask(message)&.strip
    end
  end
end
