# frozen_string_literal: true

require 'fileutils'
require_relative 'api/client'
require_relative 'atomic_file'
require_relative 'config'
require_relative 'downloader/chapter_downloader'
require_relative 'errors'
require_relative 'storage/chapter_store'
require_relative 'storage/metadata_store'
require_relative 'updates/checker'

module MangaDownloader
  # Batch mode used by cron/systemd. Downloads mangas in the order they were
  # added, resuming where the previous run stopped and never exceeding the
  # daily chapter limit.
  class AutoDownload
    STATE_VERSION = 1

    def initialize(config:, reporter:, limit: nil, only: nil, check_updates: true,
                   checker: nil, downloader_factory: nil)
      @config = config
      @reporter = reporter
      @limit = (limit || config.daily_limit).to_i
      @only = only
      @check_updates = check_updates
      @store = Storage::ChapterStore.new(config)
      @checker = checker || Updates::Checker.new(
        config: config,
        store: @store,
        metadata: Storage::MetadataStore.new(config),
        api: Api::Client.new(config, reporter: reporter),
        reporter: reporter
      )
      @downloader_factory = downloader_factory || lambda do |name, chapters|
        Downloader::ChapterDownloader.new(
          config: config, manga_name: name, chapters: chapters, reporter: reporter
        )
      end
    end

    def run
      with_lock do
        refresh_updates if @check_updates

        state = load_state
        reset_quota_if_new_day!(state)
        names = sync_queue(state)
        names = names.select { |name| name.casecmp?(@only) } if @only
        save_state(state)

        return report_empty_queue if names.empty?

        remaining = [@limit - state['downloaded_today'].to_i, 0].max
        return report_limit_reached if remaining.zero?

        @reporter.info("Daily limit: #{@limit} chapters " \
                       "(#{state['downloaded_today']} used, #{remaining} left)")

        downloaded = process_queue(names, state, remaining)
        @reporter.info("Finished: #{downloaded} chapter(s) downloaded today " \
                       "(#{state['downloaded_today']}/#{@limit}).")
      end
    end

    def status
      state = load_state
      reset_quota_if_new_day!(state)
      names = sync_queue(state)
      save_state(state)
      used = state['downloaded_today'].to_i

      @reporter.info("Date: #{state['date']}")
      @reporter.info("Used: #{used}/#{@limit} chapters")
      @reporter.info("Remaining: #{[@limit - used, 0].max}")
      @reporter.info('Queue (in order added):')

      if names.empty?
        @reporter.info('  (empty)')
      else
        names.each_with_index { |name, index| @reporter.info("  #{index + 1}. #{name}") }
      end
    end

    def reset_quota
      state = load_state
      state['date'] = today
      state['downloaded_today'] = 0
      save_state(state)
      @reporter.info("Daily download counter reset. Date: #{state['date']}")
    end

    private

    def report_empty_queue
      @reporter.info('No mangas in the download queue.')
      true
    end

    def report_limit_reached
      @reporter.info("Daily limit of #{@limit} chapters already reached. Nothing to do.")
      true
    end

    def process_queue(names, state, remaining)
      downloaded = 0

      names.each do |name|
        break if remaining <= 0

        path = @store.find_path(name)

        unless path
          @reporter.info("Skipping #{name}: no chapter list found.")
          next
        end

        @reporter.info("Downloading #{name}...")
        count = download_manga(name, path, remaining)

        next unless count.positive?

        downloaded += count
        remaining -= count
        state['downloaded_today'] = state['downloaded_today'].to_i + count
        save_state(state)
        @reporter.info("  #{count} chapter(s) downloaded. #{remaining} left today.")
      end

      downloaded
    end

    def download_manga(name, path, remaining)
      chapters = @store.load_path(path)
      summary = @downloader_factory.call(name, chapters).call(limit: remaining, skip_existing: true)
      summary.completed
    rescue NotFoundError => e
      @reporter.warn(e.message)
      0
    end

    def refresh_updates
      @checker.call.each do |update|
        additions = @checker.apply(update)
        next if additions.empty?

        @reporter.info("  #{update.name}: #{additions.size} new chapter(s)")
      end
    rescue StandardError => e
      @reporter.warn("Update check failed: #{e.message}")
    end

    def with_lock
      @config.ensure_directories!

      File.open(@config.lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          @reporter.info('Another auto-download is already running.')
          return false
        end

        yield
      end

      true
    end

    def load_state
      AtomicFile.read_json(@config.state_path, fallback: {})
    end

    def save_state(state)
      state['version'] ||= STATE_VERSION
      AtomicFile.write_json(@config.state_path, state)
    end

    def today
      Time.now.strftime('%Y-%m-%d')
    end

    def reset_quota_if_new_day!(state)
      return if state['date'] == today

      state['date'] = today
      state['downloaded_today'] = 0
    end

    # Keeps previously queued mangas in their original order and appends mangas
    # discovered later, sorted by when their chapter list was first created.
    def sync_queue(state)
      state['queue'] ||= []
      existing = @store.names
      queue = state['queue'].select { |name| existing.include?(name) }
      new_names = existing - queue
      new_names.sort_by! { |name| [added_at(@store.find_path(name)), name] }
      state['queue'] = queue + new_names
    end

    # birthtime is not available on every filesystem, so fall back to mtime.
    def added_at(path)
      return Time.at(0) unless path

      File.stat(path).birthtime
    rescue NotImplementedError, StandardError
      begin
        File.mtime(path)
      rescue StandardError
        Time.at(0)
      end
    end
  end
end
