# frozen_string_literal: true

require_relative '../test_helper'

class ChapterDownloaderTest < Minitest::Test
  include TestSupport

  class FakeNetwork
    def wait_for_idle; end
    def clear(_type); end
  end

  class FakePage
    attr_reader :body, :visited, :network

    def initialize(html)
      @body = html
      @visited = []
      @network = FakeNetwork.new
    end

    def go_to(url)
      @visited << url
    end
  end

  class FakeBrowser
    def initialize(html)
      @html = html
    end

    def create_page = FakePage.new(@html)
    def quit = nil
  end

  class FakeFetcher
    attr_reader :calls

    def initialize(results: {})
      @results = results
      @calls = []
    end

    def fetch(url, destination, chapter: nil)
      @calls << [url, File.basename(destination), chapter]
      FileUtils.mkdir_p(File.dirname(destination))
      File.write(destination, 'image')
      @results.fetch(url, true)
    end
  end

  def html_with_images(count)
    (0...count).map do |index|
      %(<div data-reader-page><img src="https://cdn/#{index}.webp"></div>)
    end.join
  end

  def build(config, chapters, fetcher: FakeFetcher.new, image_count: 2)
    MangaDownloader::Downloader::ChapterDownloader.new(
      config: config,
      manga_name: 'Berserk',
      chapters: chapter_list(chapters),
      reporter: silence_reporter,
      fetcher: fetcher,
      browser_factory: -> { FakeBrowser.new(html_with_images(image_count)) }
    )
  end

  def two_chapters
    {
      'c2' => { 'title' => 'Chapter 2', 'href' => '/read/m/c2' },
      'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' }
    }
  end

  def test_downloads_oldest_first
    with_config do |config, _dir|
      fetcher = FakeFetcher.new

      summary = build(config, two_chapters, fetcher: fetcher).call

      assert_equal 2, summary.completed
      assert_equal 0, summary.partial
      assert_equal ['Chapter 1', 'Chapter 2'], fetcher.calls.map(&:last).uniq
    end
  end

  def test_counts_only_fully_downloaded_chapters
    with_config do |config, _dir|
      fetcher = FakeFetcher.new(results: { 'https://cdn/1.webp' => false })
      chapters = { 'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' } }

      summary = build(config, chapters, fetcher: fetcher).call

      assert_equal 0, summary.completed
      assert_equal 1, summary.partial
      folder = File.join(config.mangas_dir, 'Berserk', 'Chapter 1')
      assert MangaDownloader::Downloader::ChapterMarker.partial?(folder)
    end
  end

  def test_respects_the_limit
    with_config do |config, _dir|
      fetcher = FakeFetcher.new

      summary = build(config, two_chapters, fetcher: fetcher).call(limit: 1)

      assert_equal 1, summary.completed
      assert_equal 1, fetcher.calls.map(&:last).uniq.size
    end
  end

  def test_skip_existing_leaves_complete_chapters_alone
    with_config do |config, _dir|
      folder = File.join(config.mangas_dir, 'Berserk', 'Chapter 1')
      FileUtils.mkdir_p(folder)
      File.write(File.join(folder, '001.webp'), 'image')
      chapters = { 'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' } }
      fetcher = FakeFetcher.new

      summary = build(config, chapters, fetcher: fetcher).call(skip_existing: true)

      assert_equal 1, summary.skipped
      assert_empty fetcher.calls
    end
  end

  def test_retries_a_partial_chapter_even_when_skipping
    with_config do |config, _dir|
      folder = File.join(config.mangas_dir, 'Berserk', 'Chapter 1')
      FileUtils.mkdir_p(folder)
      File.write(File.join(folder, '000.webp'), 'old-image')
      MangaDownloader::Downloader::ChapterMarker.mark_partial(folder)
      chapters = { 'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' } }
      fetcher = FakeFetcher.new

      summary = build(config, chapters, fetcher: fetcher).call(skip_existing: true)

      assert_equal 1, summary.completed
      refute MangaDownloader::Downloader::ChapterMarker.partial?(folder)
    end
  end
end
