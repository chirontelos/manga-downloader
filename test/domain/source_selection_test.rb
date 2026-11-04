# frozen_string_literal: true

require_relative '../test_helper'

class SourceSelectionTest < Minitest::Test
  include TestSupport

  def page_data(total: 4)
    {
      'scanlators' => [
        { 'id' => 's1', 'name' => 'Source One' },
        { 'id' => 's2', 'name' => 'Source Two' }
      ],
      'totalChapterCount' => total
    }
  end

  def api_chapter(id, number, source)
    {
      'id' => id,
      'title' => "Chapter #{number}",
      'number' => number,
      'index' => number,
      'scanlationMangaId' => source
    }
  end

  def build(chapters, total: 4)
    MangaDownloader::Domain::SourceSelection.build(
      page_data: page_data(total: total), all_chapters: chapters
    )
  end

  def test_marks_the_source_covering_the_whole_manga
    sources = build(
      [
        api_chapter('a1', 1, 's1'), api_chapter('a2', 2, 's1'),
        api_chapter('a3', 3, 's1'), api_chapter('a4', 4, 's1'),
        api_chapter('b1', 1, 's2')
      ]
    )

    assert sources.find { |source| source.id == 's1' }.full
    refute sources.find { |source| source.id == 's2' }.full
  end

  def test_choose_prefers_the_single_full_source
    sources = build(
      [
        api_chapter('a1', 1, 's1'), api_chapter('a2', 2, 's1'),
        api_chapter('a3', 3, 's1'), api_chapter('a4', 4, 's1'),
        api_chapter('b1', 1, 's2')
      ]
    )

    chosen = MangaDownloader::Domain::SourceSelection.choose(sources)

    assert_equal %w[s1], chosen.map(&:id)
  end

  def test_choose_uses_largest_source_when_none_is_full
    sources = build(
      [
        api_chapter('a1', 1, 's1'), api_chapter('a2', 2, 's1'),
        api_chapter('b1', 1, 's2'), api_chapter('b2', 2, 's2'), api_chapter('b3', 3, 's2')
      ]
    )

    chosen = MangaDownloader::Domain::SourceSelection.choose(sources)

    assert_equal %w[s2 s1], chosen.map(&:id)
  end

  def test_choose_asks_when_several_sources_are_full
    sources = build(
      [
        api_chapter('a1', 1, 's1'), api_chapter('a2', 2, 's1'),
        api_chapter('a3', 3, 's1'), api_chapter('a4', 4, 's1'),
        api_chapter('b1', 1, 's2'), api_chapter('b2', 2, 's2'),
        api_chapter('b3', 3, 's2'), api_chapter('b4', 4, 's2')
      ]
    )

    ui = Object.new
    def ui.ask(_prompt) = 'b'

    chosen = MangaDownloader::Domain::SourceSelection.choose(sources, ui: ui)

    assert_equal %w[s2], chosen.map(&:id)
  end

  def test_merge_fills_gaps_from_other_sources
    sources = build(
      [
        api_chapter('a1', 1, 's1'), api_chapter('a3', 3, 's1'),
        api_chapter('b1', 1, 's2'), api_chapter('b2', 2, 's2'), api_chapter('b3', 3, 's2')
      ]
    )
    primary = sources.find { |source| source.id == 's1' }
    secondary = sources.find { |source| source.id == 's2' }

    merged, used = MangaDownloader::Domain::SourceSelection.merge([primary, secondary])

    assert_equal %w[a3 b2 a1], merged.ids
    assert_equal %w[s1 s2], used.map(&:id)
  end

  def test_build_adds_read_hrefs_for_api_chapters
    sources = MangaDownloader::Domain::SourceSelection.build(
      page_data: page_data, all_chapters: [api_chapter('a1', 1, 's1')], manga_id: 'm1'
    )

    assert_equal '/read/m1/a1', sources.first.chapters.first.href
  end

  def test_merge_keeps_primary_chapter_for_duplicate_numbers
    sources = build(
      [
        api_chapter('a1', 1, 's1'),
        api_chapter('b1', 1, 's2'), api_chapter('b2', 2, 's2')
      ]
    )
    primary = sources.find { |source| source.id == 's1' }
    secondary = sources.find { |source| source.id == 's2' }

    merged, used = MangaDownloader::Domain::SourceSelection.merge([primary, secondary])

    assert_equal %w[b2 a1], merged.ids
    assert_equal %w[s1 s2], used.map(&:id)
  end
end
