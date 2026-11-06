# frozen_string_literal: true

require 'ferrum'
require 'optparse'
require_relative 'api/client'
require_relative 'auto_download'
require_relative 'config'
require_relative 'errors'
require_relative 'interactive_session'
require_relative 'reporter'
require_relative 'storage/chapter_store'
require_relative 'storage/metadata_store'
require_relative 'ui'

module MangaDownloader
  # Entry point: command-line options and the interactive menu dispatch.
  # Everything that talks to the user lives in InteractiveSession.
  class CLI
    def initialize(argv, config: Config.new, ui: UI::Console.new, reporter: nil)
      @argv = argv
      @config = config
      @ui = ui
      @reporter = reporter || Reporter.new(
        error_log_path: config.error_log_path,
        max_log_bytes: config.error_log_max_bytes
      )
      @store = Storage::ChapterStore.new(config)
      @metadata = Storage::MetadataStore.new(config)
      @api = Api::Client.new(config, reporter: @reporter)
    end

    def run
      @config.ensure_directories!

      if @argv.empty?
        interactive_session.run
        0
      else
        cli(@argv)
      end
    rescue Error => e
      @reporter.warn(e.message)
      1
    rescue Ferrum::Error => e
      @reporter.warn("Browser error: #{e.message}")
      1
    end

    private

    def interactive_session
      InteractiveSession.new(
        config: @config,
        store: @store,
        metadata: @metadata,
        api: @api,
        ui: @ui,
        reporter: @reporter
      )
    end

    def cli(argv)
      options, parser = parse_options(argv.dup)

      if options[:error]
        1
      elsif options[:help]
        print_help(parser)
        0
      else
        run_command(options, parser)
      end
    end

    def run_command(options, parser)
      auto = AutoDownload.new(
        config: @config,
        reporter: @reporter,
        limit: options[:limit],
        only: options[:manga],
        check_updates: options.fetch(:check_updates, true)
      )

      if options[:status]
        auto.status
      elsif options[:reset]
        auto.reset_quota
      elsif options[:auto]
        auto.run
      else
        print_help(parser)
        return 1
      end

      0
    end

    def print_help(parser)
      @reporter.info(parser.to_s)
    end

    def parse_options(argv)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: bin/manga [options]'
        opts.separator ''
        opts.separator 'Run without options for the interactive menu.'
        opts.separator ''
        opts.on('--auto', 'Download queued mangas without prompting (for cron)') do
          options[:auto] = true
        end
        opts.on('--limit N', Integer, "Chapters to download today (default: #{@config.daily_limit})") do |limit|
          options[:limit] = limit
        end
        opts.on('--manga NAME', 'Only process this manga') { |name| options[:manga] = name }
        opts.on('--no-update', 'Do not check for new chapters before downloading') do
          options[:check_updates] = false
        end
        opts.on('--status', 'Show the daily counter and download queue') { options[:status] = true }
        opts.on('--reset-quota', "Reset today's chapter counter") { options[:reset] = true }
        opts.on('-h', '--help', 'Show this help') { options[:help] = true }
      end

      begin
        parser.parse!(argv)
      rescue OptionParser::ParseError => e
        @reporter.warn(e.message)
        @reporter.warn(parser.to_s)
        options[:error] = true
      end

      [options, parser]
    end
  end
end
