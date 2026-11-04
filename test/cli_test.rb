# frozen_string_literal: true

require_relative 'test_helper'

class CliTest < Minitest::Test
  include TestSupport

  def build_cli(argv, config, input: StringIO.new, out: StringIO.new, err: StringIO.new)
    MangaDownloader::CLI.new(
      argv,
      config: config,
      ui: MangaDownloader::UI::Console.new(input: input, output: out),
      reporter: MangaDownloader::Reporter.new(out: out, err: err)
    )
  end

  def test_help_prints_usage_and_succeeds
    with_config do |config, _dir|
      out = StringIO.new
      status = build_cli(['--help'], config, out: out).run

      assert_equal 0, status
      assert_match(/Usage:/, out.string)
      assert_match(/--auto/, out.string)
    end
  end

  def test_invalid_option_fails
    with_config do |config, _dir|
      err = StringIO.new
      status = build_cli(['--nope'], config, err: err).run

      assert_equal 1, status
      assert_match(/invalid option/, err.string)
    end
  end

  def test_no_options_shows_help_and_fails
    with_config do |config, _dir|
      out = StringIO.new
      status = build_cli([], config, out: out).run

      # Empty argv starts the interactive menu; a closed input quits it.
      assert_equal 0, status
      assert_match(/Manga Downloader/, out.string)
    end
  end

  def test_interactive_quit_exits_cleanly
    with_config do |config, _dir|
      out = StringIO.new
      status = build_cli([], config, input: StringIO.new("q\n"), out: out).run

      assert_equal 0, status
      assert_match(/Choose an option/, out.string)
    end
  end

  def test_status_outputs_the_queue
    with_config do |config, _dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)
      store.save('Berserk', chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' }))
      out = StringIO.new

      status = build_cli(['--status'], config, out: out).run

      assert_equal 0, status
      assert_match(/Queue/, out.string)
      assert_match(/Berserk/, out.string)
    end
  end
end
