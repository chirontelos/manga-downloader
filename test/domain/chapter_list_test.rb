# frozen_string_literal: true

require_relative '../test_helper'

class ChapterListTest < Minitest::Test
  include TestSupport

  def sample_hash
    {
      'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' },
      'c3' => { 'title' => 'Chapter 3', 'href' => '/read/m/c3' },
      'c2' => { 'title' => 'Chapter 2', 'href' => '/read/m/c2' }
    }
  end

  def test_sorts_descending_by_number
    list = chapter_list(sample_hash)

    assert_equal %w[c3 c2 c1], list.ordered_descending.ids
  end

  def test_keeps_site_order_for_equal_numbers
    hash = {
      'a' => { 'title' => 'Chapter 3', 'href' => '/read/m/a' },
      'b' => { 'title' => 'Prologue 3', 'href' => '/read/m/b' }
    }

    assert_equal %w[a b], chapter_list(hash).ordered_descending.ids
  end

  def test_infers_numbers_for_untitled_entries
    hash = {
      'first' => { 'title' => 'Chapter 1', 'href' => '/read/m/first' },
      'last' => { 'title' => 'Chapter 3', 'href' => '/read/m/last' },
      'unknown' => { 'title' => 'Prologue', 'href' => '/read/m/unknown' }
    }

    ordered = chapter_list(hash).ordered_descending

    assert_equal %w[last unknown first], ordered.ids
    assert_equal 2.0, ordered.find_by_id('unknown').number
  end

  def test_leaves_list_alone_when_nothing_is_numbered
    hash = { 'a' => { 'title' => 'Prologue', 'href' => '/read/m/a' } }

    assert_equal %w[a], chapter_list(hash).ordered_descending.ids
  end

  def test_ordered_ascending_is_the_reverse
    assert_equal %w[c1 c2 c3], chapter_list(sample_hash).ordered_ascending.ids
  end

  def test_to_h_round_trips
    hash = sample_hash
    assert_equal hash, chapter_list(hash).to_h
  end

  def test_empty_list_is_safe
    assert_predicate MangaDownloader::Domain::ChapterList.new, :empty?
  end
end
