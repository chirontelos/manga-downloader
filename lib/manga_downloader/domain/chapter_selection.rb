# frozen_string_literal: true

require_relative 'chapter_list'

module MangaDownloader
  module Domain
    # Parses the user's chapter selection grammar: "100", "100-105",
    # "100,135,151" and combinations thereof. Ranges select every chapter whose
    # number falls inside the range, so "1-5" also includes 1.1, 1.2, ... 1.7.
    # Returns a ChapterList in newest-first order, matching the previous
    # behaviour.
    module ChapterSelection
      module_function

      def parse(input, chapter_list)
        ranges = parse_ranges(input)
        return ChapterList.new([]) if ranges.empty?

        selected = chapter_list.select do |chapter|
          chapter.number && ranges.any? { |range| range.cover?(chapter.number) }
        end

        ChapterList.new(
          selected.sort_by { |chapter| [-(chapter.number || 0), chapter.index || 0] }
        )
      end

      def parse_ranges(input)
        return [] if input.nil?

        input.split(',').filter_map do |part|
          part = part.strip
          next if part.empty?

          if part.include?('-')
            from, to = part.split('-', 2).map { |value| number(value) }
            next if from.nil? || to.nil?

            low, high = [from, to].minmax
            low..high
          else
            value = number(part)
            value..value if value
          end
        end
      end

      def number(value)
        Float(value.strip)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
