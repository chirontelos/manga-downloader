# frozen_string_literal: true

require_relative '../test_helper'

class ImageFetcherTest < Minitest::Test
  include TestSupport

  class FakeTransport
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = 0
    end

    def stream(_url)
      @requests += 1
      response = @responses.size > 1 ? @responses.shift : @responses.first
      raise response if response.is_a?(Exception)

      yield response[:body] if response[:body]
      response[:status]
    end

    def success?(status)
      !status.nil? && (200..299).cover?(status)
    end
  end

  def setup
    @delays = []
  end

  def build(root, retries: 0, retry_delay: 0)
    MangaDownloader::Config.new(
      root: root,
      http_retries: retries,
      http_retry_delay: retry_delay,
      chapter_delay: 0..0,
      manga_delay: 0..0
    )
  end

  def fetch(transport, config, destination)
    fetcher = MangaDownloader::Downloader::ImageFetcher.new(
      config: config, reporter: silence_reporter, transport: transport,
      sleeper: ->(seconds) { @delays << seconds }
    )
    fetcher.fetch('https://example.test/001.webp', destination, chapter: 'Chapter 1')
  end

  def test_writes_successful_download
    Dir.mktmpdir do |dir|
      dest = File.join(dir, '001.webp')
      transport = FakeTransport.new(status: 200, body: 'image-bytes')

      assert fetch(transport, build(dir), dest)
      assert_equal 'image-bytes', File.read(dest)
      refute File.exist?("#{dest}.part")
    end
  end

  def test_skips_existing_non_empty_file
    Dir.mktmpdir do |dir|
      dest = File.join(dir, '001.webp')
      File.write(dest, 'already-here')
      transport = FakeTransport.new(status: 200, body: 'new')

      assert fetch(transport, build(dir), dest)
      assert_equal 'already-here', File.read(dest)
      assert_equal 0, transport.requests
    end
  end

  def test_retries_then_succeeds
    Dir.mktmpdir do |dir|
      dest = File.join(dir, '001.webp')
      transport = FakeTransport.new({ status: 500 }, { status: 200, body: 'ok' })

      assert fetch(transport, build(dir, retries: 1), dest)
      assert_equal 'ok', File.read(dest)
      assert_equal 2, transport.requests
    end
  end

  def test_retries_wait_between_attempts
    Dir.mktmpdir do |dir|
      dest = File.join(dir, '001.webp')
      transport = FakeTransport.new({ status: 500 }, { status: 500 }, { status: 200, body: 'ok' })

      assert fetch(transport, build(dir, retries: 2, retry_delay: 1), dest)
      assert_equal [1, 1], @delays
    end
  end

  def test_gives_up_without_leaving_partial_files
    Dir.mktmpdir do |dir|
      dest = File.join(dir, '001.webp')
      transport = FakeTransport.new(status: 404, body: 'nope')

      refute fetch(transport, build(dir), dest)
      refute File.exist?(dest)
      refute File.exist?("#{dest}.part")
    end
  end

  def test_retries_on_network_error
    Dir.mktmpdir do |dir|
      dest = File.join(dir, '001.webp')
      transport = FakeTransport.new(RuntimeError.new('reset'), { status: 200, body: 'recovered' })

      assert fetch(transport, build(dir, retries: 1), dest)
      assert_equal 'recovered', File.read(dest)
    end
  end
end
