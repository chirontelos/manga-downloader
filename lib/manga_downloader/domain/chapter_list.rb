# frozen_string_literal: true

require_relative 'chapter'

module MangaDownloader
  module Domain
    # An ordered collection of chapters. Creation order is the "site order";
    # `ordered_descending` applies the numbering/ordering rules that used to
    # live in Scraper#fix_chapter_order.
    class ChapterList
      include Enumerable

      attr_reader :chapters

      def self.from_local_hash(hash)
        chapters = hash.each_with_index.map do |(id, info), index|
          Chapter.from_local(id, info, index: index)
        end
        new(chapters)
      end

      def self.from_api(array, manga_id: nil)
        chapters = Array(array).each_with_index.map do |hash, position|
          # Prefer the site's own index for tie-breaking; fall back to the
          # array position when it is absent.
          chapter = Chapter.from_api(hash, index: hash['index'] || position)
          next chapter if chapter.href || manga_id.nil?

          chapter.with(href: "/read/#{manga_id}/#{chapter.id}")
        end
        new(chapters)
      end

      def initialize(chapters = [])
        @chapters = chapters
      end

      def each(&)
        chapters.each(&)
      end

      def size = chapters.size
      def empty? = chapters.empty?
      def ids = chapters.map(&:id)
      def titles = chapters.map(&:title)

      def find_by_id(id)
        chapters.find { |chapter| chapter.id == id.to_s }
      end

      def include_id?(id)
        !find_by_id(id).nil?
      end

      # Sorts newest-first by chapter number and fills in numbers for untitled
      # entries so they land in their correct numeric spot. Ties keep the
      # original site order.
      def ordered_descending
        known = chapters.filter_map(&:number)
        return self if known.empty?

        missing = ((known.min.to_i)..(known.max.to_i)).to_a - known.map(&:to_i)
        missing.sort!

        numbered = chapters.map do |chapter|
          next chapter if chapter.number

          inferred = missing.shift || (known.min - 1)
          chapter.with_number(inferred.to_f)
        end

        self.class.new(
          numbered.sort_by { |chapter| [-(chapter.number || 0), chapter.index || 0] }
        )
      end

      # Download order: oldest first, as the downloader has always done.
      def ordered_ascending
        self.class.new(ordered_descending.chapters.reverse)
      end

      def to_h
        chapters.to_h { |chapter| [chapter.id, chapter.to_local] }
      end
    end
  end
end
