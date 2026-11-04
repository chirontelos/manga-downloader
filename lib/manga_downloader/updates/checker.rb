# frozen_string_literal: true

require_relative '../atomic_file'
require_relative '../domain/chapter_list'
require_relative '../manga_id'

module MangaDownloader
  module Updates
    # Finds new chapters for saved mangas and applies them to disk. Only
    # ongoing/hiatus mangas are checked; completed ones are skipped using the
    # metadata cache so they aren't fetched again.
    class Checker
      TRACKED_STATUSES = %w[ongoing hiatus].freeze
      Update = Data.define(:name, :path, :id, :href, :status, :new_chapters, :existing_chapters)

      def initialize(config:, store:, metadata:, api:, reporter:)
        @config = config
        @store = store
        @metadata = metadata
        @api = api
        @reporter = reporter
      end

      def call
        @store.all_paths.filter_map { |path| check_path(path) }
      end

      # Writes the new chapters into the manga's JSON file (newest first) and
      # returns just the additions, which is what the downloader needs.
      def apply(update)
        additions = update.new_chapters.each_with_object({}) do |chapter, hash|
          next if update.existing_chapters.key?(chapter['id'])

          hash[chapter['id']] = {
            'title' => chapter['title'],
            'href' => "/read/#{update.id}/#{chapter['id']}"
          }
        end
        return {} if additions.empty?

        @store.save_path(update.path, additions.merge(update.existing_chapters))
        additions
      end

      def trackable?(status)
        TRACKED_STATUSES.include?(status.to_s.downcase)
      end

      private

      def check_path(path)
        name = File.basename(path, '.json')
        return nil if Storage::ChapterStore::TEMP_SUFFIXES.any? { |suffix| name.end_with?(suffix) }

        existing = AtomicFile.read_json(path, fallback: nil)
        return nil unless existing

        id = MangaId.from_local_hash(existing)
        return nil unless id

        status = @metadata.status(id)
        return nil if status && !trackable?(status)

        page = @api.manga_page(id)
        return nil unless page

        status = page['status']
        @metadata.record("/manga/#{id}", status: status)
        return nil unless trackable?(status)

        new_chapters = new_chapters_for(page, id, existing)
        return nil if new_chapters.empty?

        Update.new(
          name: name, path: path, id: id, href: "/manga/#{id}",
          status: status, new_chapters: new_chapters, existing_chapters: existing
        )
      end

      def new_chapters_for(page, id, existing)
        source_ids = source_ids_for(id, page['chapters'] || [], existing)
        candidates = candidate_chapters(page, id, existing, source_ids)
        filter_new_chapters(candidates, existing)
      end

      def candidate_chapters(page, id, existing, source_ids)
        latest = filter_by_sources(page['chapters'] || [], source_ids)
        overlap = latest.any? { |chapter| existing.key?(chapter['id']) }
        return latest unless !overlap && page['totalChapterCount'].to_i > existing.size

        # The local copy is far behind; fetch the full list so no chapter is missed.
        full = @api.all_chapters(id)
        return latest unless full

        filter_by_sources(full, source_ids)
      end

      def filter_by_sources(chapters, source_ids)
        return chapters if source_ids.empty?

        chapters.select { |chapter| source_ids.include?(chapter['scanlationMangaId']) }
      end

      def filter_new_chapters(candidates, existing)
        max_saved_number = candidates.filter_map do |chapter|
          chapter['number'] if existing.key?(chapter['id'])
        end.max

        new_chapters = if max_saved_number
                         candidates.select { |chapter| chapter['number'] && chapter['number'] > max_saved_number }
                       else
                         candidates.reject { |chapter| existing.key?(chapter['id']) }
                       end

        new_chapters.sort_by { |chapter| [-(chapter['number'] || 0), -(chapter['index'] || 0)] }
      end

      def source_ids_for(id, latest, existing)
        source_ids = @metadata.source_ids(id)
        return source_ids unless source_ids.empty?

        source_ids = latest.filter_map { |chapter| chapter['scanlationMangaId'] if existing.key?(chapter['id']) }.uniq
        @metadata.record("/manga/#{id}", source_ids: source_ids) unless source_ids.empty?
        source_ids
      end
    end
  end
end
