# frozen_string_literal: true

require_relative '../test_helper'

class ChapterTest < Minitest::Test
  include TestSupport

  def test_parses_number_from_title
    assert_equal 12.0, MangaDownloader::Domain::Chapter.number_from_title('Chapter 12')
    assert_equal 3.5, MangaDownloader::Domain::Chapter.number_from_title('Chapter 3.5')
    assert_nil MangaDownloader::Domain::Chapter.number_from_title('Prologue')
    assert_nil MangaDownloader::Domain::Chapter.number_from_title(nil)
  end

  def test_from_local_parses_title_number
    chapter = MangaDownloader::Domain::Chapter.from_local('c1', { 'title' => 'Chapter 7', 'href' => '/read/m/c1' })

    assert_equal 'c1', chapter.id
    assert_equal 7.0, chapter.number
    assert_equal({ 'title' => 'Chapter 7', 'href' => '/read/m/c1' }, chapter.to_local)
  end

  def test_from_api_keeps_missing_number_nil
    chapter = MangaDownloader::Domain::Chapter.from_api(
      { 'id' => 'c1', 'title' => 'Chapter 7', 'number' => nil, 'scanlationMangaId' => 's1' }
    )

    assert_nil chapter.number, 'API numbers must not be inferred from titles'
    assert_equal 's1', chapter.source_id
  end

  def test_key_uses_id_when_unnumbered
    chapter = MangaDownloader::Domain::Chapter.new(id: 'c1', title: 'Prologue')

    assert_equal 'id:c1', chapter.key
  end
end
