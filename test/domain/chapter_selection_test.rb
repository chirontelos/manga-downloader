# frozen_string_literal: true

require_relative '../test_helper'

class ChapterSelectionTest < Minitest::Test
  include TestSupport

  def setup
    @list = chapter_list(
      'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' },
      'c2' => { 'title' => 'Chapter 2', 'href' => '/read/m/c2' },
      'c3' => { 'title' => 'Chapter 3', 'href' => '/read/m/c3' },
      'c10' => { 'title' => 'Chapter 10', 'href' => '/read/m/c10' },
      'half' => { 'title' => 'Chapter 1.5', 'href' => '/read/m/half' }
    )
  end

  def parse(input)
    MangaDownloader::Domain::ChapterSelection.parse(input, @list)
  end

  def test_single_number
    assert_equal %w[c2], parse('2').ids
  end

  def test_comma_separated_numbers_are_newest_first
    assert_equal %w[c10 c2], parse('2,10').ids
  end

  def test_range
    assert_equal %w[c3 c2 half c1], parse('1-3').ids
  end

  def test_range_includes_decimal_chapters
    list = chapter_list(
      'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' },
      'c11' => { 'title' => 'Chapter 1.1', 'href' => '/read/m/c11' },
      'c12' => { 'title' => 'Chapter 1.2', 'href' => '/read/m/c12' },
      'c17' => { 'title' => 'Chapter 1.7', 'href' => '/read/m/c17' },
      'c2' => { 'title' => 'Chapter 2', 'href' => '/read/m/c2' },
      'c5' => { 'title' => 'Chapter 5', 'href' => '/read/m/c5' }
    )

    selected = MangaDownloader::Domain::ChapterSelection.parse('1-2', list)

    assert_equal %w[c2 c17 c12 c11 c1], selected.ids
  end

  def test_range_boundaries_are_exact
    assert_equal %w[c1], parse('1-1').ids
    assert_equal %w[half], parse('1.5-1.5').ids
  end

  def test_ignores_invalid_numbers
    assert_empty parse('nope')
    assert_equal %w[c2], parse('2,nope').ids
  end

  def test_reversed_range
    assert_equal %w[c3 c2 half c1], parse('3-1').ids
  end

  def test_decimal_number
    assert_equal %w[half], parse('1.5').ids
  end

  def test_duplicates_are_collapsed
    assert_equal %w[c2], parse('2,2,2').ids
  end

  def test_empty_input_selects_nothing
    assert_predicate parse(''), :empty?
    assert_predicate parse(nil), :empty?
  end

  def test_unknown_numbers_are_ignored
    assert_equal %w[c2], parse('2,99').ids
  end
end
