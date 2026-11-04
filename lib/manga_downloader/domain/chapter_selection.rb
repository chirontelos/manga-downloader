# frozen_string_literal: true

require_relative 'chapter_list'

module MangaDownloader
  module Domain
    # Parses the user's chapter selection grammar: "100", "100-105",
    # "100,135,151" and combinations thereof. Returns a ChapterList in
    # newest-first order, matching the previous behaviour.
    module ChapterSelection
      module_function

      def parse(input, chapter_list)
        numbers = parse_numbers(input)
        return ChapterList.new([]) if numbers.empty?

        by_number = {}
        chapter_list.each do |chapter|
          by_number[chapter.number] = chapter unless chapter.number.nil?
        end

        selected = numbers.uniq.sort.reverse.filter_map { |number| by_number[number] }
        ChapterList.new(selected)
      end

      def parse_numbers(input)
        return [] if input.nil?

        input.split(',').flat_map do |part|
          part = part.strip
          next [] if part.empty?

          if part.include?('-')
            from, to = part.split('-').map { |value| value.strip.to_f }
            from, to = [from, to].minmax
            (from.to_i..to.to_i).map(&:to_f)
          else
            [part.to_f]
          end
        end
      end
    end
  end
end
