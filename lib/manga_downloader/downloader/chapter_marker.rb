# frozen_string_literal: true

require 'fileutils'
require 'time'
require_relative '../atomic_file'

module MangaDownloader
  module Downloader
    # Completion bookkeeping for one chapter folder. A `.partial` marker means
    # the chapter was interrupted, so the next run retries it instead of
    # treating any non-empty folder as finished. Folders from older versions
    # (no marker) are still considered complete.
    module ChapterMarker
      PARTIAL_FILE = '.partial'

      module_function

      def complete?(dir)
        Dir.exist?(dir) && !Dir.empty?(dir) && !partial?(dir)
      end

      def partial?(dir)
        File.exist?(File.join(dir, PARTIAL_FILE))
      end

      def mark_partial(dir)
        FileUtils.mkdir_p(dir)
        AtomicFile.write(File.join(dir, PARTIAL_FILE), Time.now.utc.iso8601)
      end

      def mark_complete(dir)
        FileUtils.rm_f(File.join(dir, PARTIAL_FILE))
      end
    end
  end
end
