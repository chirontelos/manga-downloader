# frozen_string_literal: true

require 'fileutils'
require_relative '../atomic_file'
require_relative '../errors'
require_relative '../naming'
require_relative '../domain/chapter_list'

module MangaDownloader
  module Storage
    # Persists chapter lists in jsons/<Manga Name>.json. All path derivation
    # and name lookup lives here, so nothing else has to know the layout.
    class ChapterStore
      TEMP_SUFFIXES = %w[_selection_tmp _update_tmp].freeze

      def initialize(config)
        @config = config
      end

      def path_for(name)
        File.join(@config.jsons_dir, "#{Naming.sanitize(name)}.json")
      end

      def find_path(name)
        target = Naming.sanitize(name).downcase
        all_paths.find { |path| File.basename(path, '.json').downcase == target }
      end

      def exist?(name)
        !find_path(name).nil?
      end

      def load(name)
        path = find_path(name)
        raise NotFoundError, "No chapter list found for \"#{name}\"" unless path

        load_path(path)
      end

      def load_path(path)
        raw = AtomicFile.read_json(path, fallback: nil)
        raise NotFoundError, "Could not read chapter list #{path}" if raw.nil?

        Domain::ChapterList.from_local_hash(raw)
      end

      def load_hash(name)
        path = find_path(name)
        raise NotFoundError, "No chapter list found for \"#{name}\"" unless path

        AtomicFile.read_json(path, fallback: {})
      end

      def save(name, chapter_list)
        save_path(path_for(name), chapter_list)
      end

      def save_path(path, chapter_list)
        hash = chapter_list.respond_to?(:to_h) ? chapter_list.to_h : chapter_list
        AtomicFile.write_json(path, hash)
      end

      def all_paths
        Dir.glob(File.join(@config.jsons_dir, '*.json'))
      end

      # Names of the saved mangas, in filesystem order, excluding temp files.
      def names
        all_paths.filter_map do |path|
          name = File.basename(path, '.json')
          next if TEMP_SUFFIXES.any? { |suffix| name.end_with?(suffix) }

          name
        end
      end
    end
  end
end
