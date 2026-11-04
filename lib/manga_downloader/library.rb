# frozen_string_literal: true

require 'fileutils'
require_relative 'errors'
require_relative 'naming'
require_relative 'downloader/chapter_marker'

module MangaDownloader
  # Read-only view of what has been downloaded versus only queued.
  class Library
    def initialize(config:, store:)
      @config = config
      @store = store
    end

    # Returns [downloaded_names, pending_names].
    def list_mangas
      downloaded = []
      pending = []

      @store.names.each do |name|
        (downloaded?(name) ? downloaded : pending) << name
      end

      [downloaded, pending]
    end

    def downloaded?(name, path: nil)
      path ||= @store.find_path(name)
      return false unless path

      folder = File.join(@config.mangas_dir, Naming.path_segment(name))
      return false unless Dir.exist?(folder)

      expected = @store.load_path(path).size
      return false if expected.zero?

      actual = Dir.children(folder).count do |child|
        Downloader::ChapterMarker.complete?(File.join(folder, child))
      end

      actual == expected
    end
  end
end
