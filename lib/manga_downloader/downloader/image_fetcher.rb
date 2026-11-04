# frozen_string_literal: true

require 'fileutils'
require 'uri'
require_relative '../http_transport'

module MangaDownloader
  module Downloader
    # Downloads one image, retries a few times, and logs only the failures that
    # survive every attempt. Existing non-empty files are skipped so an
    # interrupted chapter resumes instead of starting over.
    class ImageFetcher
      def initialize(config:, reporter:, manga_name: nil, transport: nil,
                     sleeper: ->(seconds) { sleep(seconds) })
        @config = config
        @reporter = reporter
        @manga_name = manga_name
        @transport = transport || HttpTransport.new(config, reporter: reporter)
        @sleeper = sleeper
      end

      def fetch(url, dest_path, chapter: nil)
        return true if complete_file?(dest_path)

        partial_path = "#{dest_path}.part"
        attempt = 0

        begin
          attempt += 1
          write_image(url, partial_path)
          File.rename(partial_path, dest_path)
          true
        rescue StandardError => e
          FileUtils.rm_f(partial_path)

          if attempt <= @config.http_retries
            @sleeper.call(@config.http_retry_delay)
            retry
          end

          @reporter.error(
            "image failed after #{attempt} attempts: #{url} (#{e.class}: #{e.message})",
            manga: @manga_name, chapter: chapter
          )
          false
        end
      end

      private

      def complete_file?(path)
        File.exist?(path) && File.size(path).positive?
      end

      def write_image(url, path)
        FileUtils.mkdir_p(File.dirname(path))

        File.open(path, 'wb') do |file|
          status = @transport.stream(url) { |chunk| file.write(chunk) }
          raise Error, "HTTP #{status}" unless @transport.success?(status)
        end
      end
    end
  end
end
