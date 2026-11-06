# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module MangaDownloader
  # All tunable values and filesystem locations live here. Nothing else may
  # call Dir.pwd or embed a sleep/timeout literal, so the behaviour can be
  # changed (and tested) in one place.
  class Config
    PROJECT_ROOT = File.expand_path('../..', __dir__)

    attr_reader :root, :base_url, :browser_path, :headless, :page_timeout,
                :protocol_timeout, :chapter_retries,
                :http_open_timeout, :http_read_timeout, :http_retries,
                :http_retry_delay, :image_threads, :daily_limit,
                :chapter_delay, :manga_delay, :navigation_delay,
                :scroll_delay, :bottom_delay, :scroll_step,
                :scroll_up_step, :max_scroll_iterations, :max_settle_attempts,
                :stale_iterations_before_stop, :quiet_iterations_before_stop,
                :error_log_max_bytes

    MAX_IMAGE_THREADS = 20

    def initialize(
      root: ENV.fetch('MANGA_HOME', PROJECT_ROOT),
      base_url: ENV.fetch('MANGA_BASE_URL', 'https://atsu.moe'),
      browser_path: ENV['CHROMIUM_PATH'] || default_browser_path,
      headless: true,
      page_timeout: nil,
      protocol_timeout: nil,
      chapter_retries: nil,
      http_open_timeout: nil,
      http_read_timeout: nil,
      http_retries: nil,
      http_retry_delay: nil,
      image_threads: nil,
      daily_limit: nil,
      chapter_delay: 3..10,
      manga_delay: 10..20,
      navigation_delay: 1.0,
      scroll_delay: 0.6,
      bottom_delay: 2.0,
      scroll_step: 800,
      scroll_up_step: 700,
      max_scroll_iterations: 500,
      max_settle_attempts: 8,
      stale_iterations_before_stop: 3,
      quiet_iterations_before_stop: 3,
      error_log_max_bytes: 1_048_576
    )
      @root = File.expand_path(root)
      @base_url = base_url
      @browser_path = browser_path
      @headless = headless
      @page_timeout = page_timeout || self.class.env_float('MANGA_PAGE_TIMEOUT', 60)
      @protocol_timeout = protocol_timeout || self.class.env_float('MANGA_PROTOCOL_TIMEOUT', 120)
      @chapter_retries = chapter_retries || self.class.env_int('MANGA_CHAPTER_RETRIES', 1)
      @http_open_timeout = http_open_timeout || self.class.env_float('MANGA_HTTP_OPEN_TIMEOUT', 60)
      @http_read_timeout = http_read_timeout || self.class.env_float('MANGA_HTTP_READ_TIMEOUT', 60)
      @http_retries = http_retries || self.class.env_int('MANGA_HTTP_RETRIES', 3)
      @http_retry_delay = http_retry_delay || self.class.env_float('MANGA_HTTP_RETRY_DELAY', 2)
      @image_threads = (image_threads || self.class.env_int('MANGA_IMAGE_THREADS', 10)).clamp(1, MAX_IMAGE_THREADS)
      @daily_limit = daily_limit || self.class.env_int('MANGA_DAILY_LIMIT', 300)
      @chapter_delay = chapter_delay
      @manga_delay = manga_delay
      @navigation_delay = navigation_delay
      @scroll_delay = scroll_delay
      @bottom_delay = bottom_delay
      @scroll_step = scroll_step
      @scroll_up_step = scroll_up_step
      @max_scroll_iterations = max_scroll_iterations
      @max_settle_attempts = max_settle_attempts
      @stale_iterations_before_stop = stale_iterations_before_stop
      @quiet_iterations_before_stop = quiet_iterations_before_stop
      @error_log_max_bytes = error_log_max_bytes
    end

    def self.env_int(key, default)
      value = ENV.fetch(key, nil)
      value.nil? || value.strip.empty? ? default : Integer(value)
    rescue ArgumentError
      default
    end

    def self.env_float(key, default)
      value = ENV.fetch(key, nil)
      value.nil? || value.strip.empty? ? default : Float(value)
    rescue ArgumentError
      default
    end

    def jsons_dir = File.join(root, 'jsons')
    def mangas_dir = File.join(root, 'mangas')
    def metadata_path = File.join(jsons_dir, '.manga_metadata.json')
    def state_path = File.join(jsons_dir, '.download_state.json')
    def lock_path = File.join(jsons_dir, '.download.lock')
    def error_log_path = File.join(root, 'download_errors.log')
    def api_base = "#{base_url}/api"

    def chapter_delay_seconds = rand(chapter_delay)
    def manga_delay_seconds = rand(manga_delay)

    def ensure_directories!
      FileUtils.mkdir_p(jsons_dir)
      FileUtils.mkdir_p(mangas_dir)
    end

    private

    def default_browser_path
      path = '/usr/local/bin/chromium'
      path if File.executable?(path)
    end
  end
end
