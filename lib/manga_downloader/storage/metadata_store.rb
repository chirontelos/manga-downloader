# frozen_string_literal: true

require 'time'
require_relative '../atomic_file'
require_relative '../manga_id'

module MangaDownloader
  module Storage
    # Small cache of site metadata (status, scanlation sources) keyed by manga
    # id. Lets update checks skip completed mangas without re-fetching them.
    class MetadataStore
      def initialize(config)
        @config = config
      end

      def load
        AtomicFile.read_json(@config.metadata_path, fallback: {})
      end

      def status(id)
        load.dig(id.to_s, 'status')
      end

      def source_ids(id)
        entry = load[id.to_s] || {}
        Array(entry['source_ids'] || entry['source_id']).compact.uniq
      end

      def record(manga_href, status: nil, source_id: nil, source_ids: nil)
        id = MangaId.from_href(manga_href)
        return unless id

        metadata = load
        entry = metadata[id] ||= { 'href' => "/manga/#{id}" }
        entry['status'] = status if status
        entry['source_id'] = source_id unless source_id.nil?
        entry['source_ids'] = source_ids unless source_ids.nil?
        entry['checked_at'] = Time.now.utc.iso8601
        AtomicFile.write_json(@config.metadata_path, metadata)
      end
    end
  end
end
