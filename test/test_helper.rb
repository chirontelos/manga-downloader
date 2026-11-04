# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require 'manga_downloader'

module TestSupport
  def build_config(root)
    MangaDownloader::Config.new(
      root: root,
      http_retries: 0,
      http_retry_delay: 0,
      navigation_delay: 0,
      scroll_delay: 0,
      bottom_delay: 0,
      chapter_delay: 0..0,
      manga_delay: 0..0
    )
  end

  def with_config
    Dir.mktmpdir do |dir|
      config = build_config(dir)
      config.ensure_directories!
      yield config, dir
    end
  end

  def silence_reporter
    MangaDownloader::Reporter.new(out: StringIO.new, err: StringIO.new)
  end

  def chapter_list(hash)
    MangaDownloader::Domain::ChapterList.from_local_hash(hash)
  end
end
