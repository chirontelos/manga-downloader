# frozen_string_literal: true

require_relative 'test_helper'

class ConfigTest < Minitest::Test
  include TestSupport

  ENV_KEYS = %w[
    MANGA_HTTP_OPEN_TIMEOUT MANGA_HTTP_READ_TIMEOUT MANGA_HTTP_RETRIES
    MANGA_HTTP_RETRY_DELAY MANGA_IMAGE_THREADS MANGA_DAILY_LIMIT
    MANGA_PAGE_TIMEOUT MANGA_PROTOCOL_TIMEOUT MANGA_CHAPTER_RETRIES
  ].freeze

  def with_env(values)
    saved = ENV_KEYS.to_h { |key| [key, ENV.fetch(key, nil)] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    values.each { |key, value| ENV[key] = value }

    yield
  ensure
    ENV_KEYS.each { |key| saved[key] ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  def test_env_overrides_network_settings
    with_env(
      'MANGA_HTTP_OPEN_TIMEOUT' => '25',
      'MANGA_HTTP_READ_TIMEOUT' => '45',
      'MANGA_HTTP_RETRIES' => '5',
      'MANGA_HTTP_RETRY_DELAY' => '1.5',
      'MANGA_IMAGE_THREADS' => '3',
      'MANGA_DAILY_LIMIT' => '100',
      'MANGA_PAGE_TIMEOUT' => '75',
      'MANGA_PROTOCOL_TIMEOUT' => '150',
      'MANGA_CHAPTER_RETRIES' => '2'
    ) do
      Dir.mktmpdir do |dir|
        config = MangaDownloader::Config.new(root: dir)

        assert_equal 25.0, config.http_open_timeout
        assert_equal 45.0, config.http_read_timeout
        assert_equal 5, config.http_retries
        assert_equal 1.5, config.http_retry_delay
        assert_equal 3, config.image_threads
        assert_equal 100, config.daily_limit
        assert_equal 75.0, config.page_timeout
        assert_equal 150.0, config.protocol_timeout
        assert_equal 2, config.chapter_retries
      end
    end
  end

  def test_invalid_env_values_fall_back_to_defaults
    with_env('MANGA_HTTP_RETRIES' => 'nope', 'MANGA_IMAGE_THREADS' => '1.5') do
      Dir.mktmpdir do |dir|
        config = MangaDownloader::Config.new(root: dir)

        assert_equal 3, config.http_retries
        assert_equal 10, config.image_threads
      end
    end
  end

  def test_image_threads_are_capped_at_twenty
    with_env('MANGA_IMAGE_THREADS' => '50') do
      Dir.mktmpdir do |dir|
        assert_equal 20, MangaDownloader::Config.new(root: dir).image_threads
      end
    end

    with_env('MANGA_IMAGE_THREADS' => '0') do
      Dir.mktmpdir do |dir|
        assert_equal 1, MangaDownloader::Config.new(root: dir).image_threads
      end
    end
  end

  def test_explicit_values_win_over_env
    with_env('MANGA_HTTP_OPEN_TIMEOUT' => '25', 'MANGA_PAGE_TIMEOUT' => '75') do
      Dir.mktmpdir do |dir|
        config = MangaDownloader::Config.new(root: dir, http_open_timeout: 7, page_timeout: 20)

        assert_equal 7, config.http_open_timeout
        assert_equal 20, config.page_timeout
      end
    end
  end
end
