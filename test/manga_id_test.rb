# frozen_string_literal: true

require_relative 'test_helper'

class MangaIdTest < Minitest::Test
  include TestSupport

  def test_from_input_accepts_manga_urls
    assert_equal 'CM0wz', MangaDownloader::MangaId.from_input('https://atsu.moe/manga/CM0wz')
    assert_equal 'CM0wz', MangaDownloader::MangaId.from_input('https://atsu.moe/manga/CM0wz/')
    assert_nil MangaDownloader::MangaId.from_input('Berserk')
  end

  def test_from_href
    assert_equal 'CM0wz', MangaDownloader::MangaId.from_href('/manga/CM0wz')
    assert_nil MangaDownloader::MangaId.from_href('/read/CM0wz/c1')
  end

  def test_from_local_hash_uses_read_hrefs
    hash = { 'c1' => { 'title' => 'Chapter 1', 'href' => '/read/CM0wz/c1' } }

    assert_equal 'CM0wz', MangaDownloader::MangaId.from_local_hash(hash)
    assert_nil MangaDownloader::MangaId.from_local_hash({})
  end

  def test_from_chapter_list
    list = chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/CM0wz/c1' })

    assert_equal 'CM0wz', MangaDownloader::MangaId.from_chapter_list(list)
  end
end
