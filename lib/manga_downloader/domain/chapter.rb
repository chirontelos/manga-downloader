# frozen_string_literal: true

module MangaDownloader
  module Domain
    # Number embedded in a chapter title, e.g. "Chapter 12" or "Chapter 3.5".
    TITLE_NUMBER = /(\d+(?:\.\d+)?)/

    # A single chapter, independent of where it came from (local JSON or the
    # site API). `number` is the ordering key; `index` preserves the site's
    # original order so ties (e.g. "Chapter 3" / "Prologue 3") stay stable.
    Chapter = Data.define(:id, :title, :href, :number, :index, :source_id) do
      def initialize(id:, title: nil, href: nil, number: nil, index: nil, source_id: nil)
        super(
          id: id.to_s,
          title: title,
          href: href,
          number: number&.to_f,
          index: index,
          source_id: source_id
        )
      end

      def self.number_from_title(title)
        return nil if title.nil?

        match = title[Domain::TITLE_NUMBER, 1]
        match&.to_f
      end

      def self.from_local(id, hash, index: nil)
        new(id: id, title: hash['title'], href: hash['href'],
            number: number_from_title(hash['title']), index: index)
      end

      def self.from_api(hash, index: nil)
        new(
          id: hash['id'],
          title: hash['title'],
          href: hash['href'],
          number: hash['number'],
          index: index.nil? ? hash['index'] : index,
          source_id: hash['scanlationMangaId']
        )
      end

      # Shape used by the on-disk chapter lists (and therefore by the
      # downloader), matching the original file format.
      def to_local
        { 'title' => title, 'href' => href }
      end

      def with_number(value)
        with(number: value)
      end

      def key
        number.nil? ? "id:#{id}" : number
      end
    end
  end
end
