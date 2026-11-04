# frozen_string_literal: true

require_relative 'chapter'
require_relative 'chapter_list'
require_relative '../labels'

module MangaDownloader
  module Domain
    # Decides which scanlation source(s) to use for a manga. If one source
    # covers everything, it wins; otherwise the largest source is used and its
    # gaps are filled from the others.
    class SourceSelection
      Source = Struct.new(:id, :name, :chapters, :chapter_count, :full, :label, keyword_init: true)

      def self.build(page_data:, all_chapters:, manga_id: nil)
        scanlators = page_data ? page_data['scanlators'] || [] : []
        names = scanlators.to_h { |source| [source['id'], source['name']] }
        groups = all_chapters.group_by { |chapter| chapter['scanlationMangaId'] }

        all_numbers = all_chapters.filter_map { |chapter| chapter['number'] }
        global_min, global_max = all_numbers.minmax
        total = page_data ? page_data['totalChapterCount'].to_f : 0.0

        groups.map do |source_id, raw_chapters|
          chapter_list = ChapterList.from_api(raw_chapters, manga_id: manga_id)
          numbers = chapter_list.filter_map(&:number)

          Source.new(
            id: source_id,
            name: names[source_id] || source_id,
            chapters: chapter_list,
            chapter_count: chapter_list.size,
            full: full?(numbers, chapter_list.size, total, global_min, global_max)
          )
        end
      end

      def self.full?(numbers, chapter_count, total, global_min, global_max)
        if total.positive?
          !numbers.max.nil? && numbers.max >= total && chapter_count >= total
        else
          !global_min.nil? && !global_max.nil? && !numbers.min.nil? && !numbers.max.nil? &&
            numbers.min <= global_min && numbers.max >= global_max
        end
      end

      def self.choose(sources, ui: nil, reporter: nil)
        full_sources = sources.select(&:full)

        if full_sources.size == 1
          chosen = full_sources.first
          reporter&.info("Using source #{chosen.name} (has the entire manga).")
          return [chosen]
        end

        return [ask_source(full_sources, ui: ui, reporter: reporter)] if full_sources.size > 1

        primary = sources.max_by(&:chapter_count)
        [primary, *sources.reject { |source| source.equal?(primary) }.sort_by { |source| -source.chapter_count }]
      end

      def self.ask_source(candidates, ui:, reporter: nil)
        labels = Labels.for(candidates.size)
        candidates.each_with_index { |source, index| source.label = labels[index] }

        reporter&.info('Multiple sources available:')
        candidates.each do |source|
          reporter&.info("[#{source.label}] #{source.name} (#{source.chapter_count} chapters)")
        end

        loop do
          input = ui&.ask('Choose a source: ')&.downcase
          return candidates.first if input.nil?

          chosen = candidates.find { |source| source.label == input }
          return chosen if chosen

          reporter&.warn('Invalid selection.')
        end
      end

      # Merges the chosen sources, keeping the first source's chapter when two
      # sources provide the same number.
      def self.merge(sources)
        primary = sources.first
        by_key = {}

        primary.chapters.each { |chapter| by_key[chapter.key] ||= chapter }

        used_sources = [primary]
        sources.drop(1).each do |source|
          added = false
          source.chapters.each do |chapter|
            next if by_key.key?(chapter.key)

            by_key[chapter.key] = chapter
            added = true
          end
          used_sources << source if added
        end

        ordered = by_key.values.sort_by do |chapter|
          [-(chapter.number || 0), -(chapter.index || 0)]
        end

        [ChapterList.new(ordered), used_sources]
      end
    end
  end
end
