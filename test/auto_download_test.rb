# frozen_string_literal: true

require_relative 'test_helper'

class AutoDownloadTest < Minitest::Test
  include TestSupport

  Summary = MangaDownloader::Downloader::ChapterDownloader::Summary

  class FakeChecker
    def call = []
    def apply(_update) = {}
  end

  class FakeDownloader
    def initialize(summary, calls, limit_cap)
      @summary = summary
      @calls = calls
      @limit_cap = limit_cap
    end

    def call(limit:, skip_existing:)
      @calls << [limit, skip_existing]
      completed = [@summary.completed, limit || @limit_cap].min
      @summary.with(completed: completed)
    end
  end

  def setup
    @out = StringIO.new
    @reporter = MangaDownloader::Reporter.new(out: @out, err: StringIO.new)
  end

  def seed(config, names)
    store = MangaDownloader::Storage::ChapterStore.new(config)
    names.each do |name|
      store.save(name, chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => "/read/#{name}/c1" }))
    end
    store
  end

  def build(config, calls, completed: 2)
    MangaDownloader::AutoDownload.new(
      config: config,
      reporter: @reporter,
      limit: 3,
      check_updates: false,
      checker: FakeChecker.new,
      downloader_factory: lambda do |_name, _chapters|
        FakeDownloader.new(Summary.empty.with(completed: completed), calls, completed)
      end
    )
  end

  def test_downloads_up_to_the_daily_limit_and_persists_state
    with_config do |config, _dir|
      seed(config, %w[Alpha Beta])
      calls = []
      build(config, calls).run

      assert_equal [[3, true], [1, true]], calls
      state = MangaDownloader::AtomicFile.read_json(config.state_path)
      assert_equal 3, state['downloaded_today']
      assert_equal 1, state['version']
    end
  end

  def test_does_nothing_once_the_limit_is_reached
    with_config do |config, _dir|
      seed(config, %w[Alpha])
      MangaDownloader::AtomicFile.write_json(
        config.state_path,
        'date' => Time.now.strftime('%Y-%m-%d'),
        'downloaded_today' => 3,
        'queue' => ['Alpha']
      )
      calls = []
      build(config, calls).run

      assert_empty calls
      assert_match(/already reached/, @out.string)
    end
  end

  def test_resets_quota_on_a_new_day
    with_config do |config, _dir|
      seed(config, %w[Alpha])
      MangaDownloader::AtomicFile.write_json(
        config.state_path,
        'date' => '2000-01-01',
        'downloaded_today' => 99,
        'queue' => ['Alpha']
      )
      calls = []
      build(config, calls, completed: 1).run

      assert_equal 1, calls.size
      state = MangaDownloader::AtomicFile.read_json(config.state_path)
      assert_equal 1, state['downloaded_today']
    end
  end

  def test_filters_by_manga_name
    with_config do |config, _dir|
      seed(config, %w[Alpha Beta])
      calls = []
      auto = MangaDownloader::AutoDownload.new(
        config: config, reporter: @reporter, limit: 3, only: 'beta',
        check_updates: false, checker: FakeChecker.new,
        downloader_factory: ->(_name, _chapters) { FakeDownloader.new(Summary.empty.with(completed: 1), calls, 1) }
      )
      auto.run

      assert_equal [[3, true]], calls
      assert_match(/Downloading Beta/, @out.string)
      refute_match(/Downloading Alpha/, @out.string)
    end
  end

  def test_refuses_to_run_when_lock_is_held
    with_config do |config, _dir|
      seed(config, %w[Alpha])
      calls = []

      File.open(config.lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX | File::LOCK_NB)
        build(config, calls).run
      end

      assert_empty calls
      assert_match(/already running/, @out.string)
    end
  end
end
