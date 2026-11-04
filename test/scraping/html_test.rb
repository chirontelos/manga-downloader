# frozen_string_literal: true

require_relative '../test_helper'

class HtmlTest < Minitest::Test
  include TestSupport

  Html = MangaDownloader::Scraping::Html

  def test_extracts_chapter_links_and_ignores_start_reading
    html = <<~HTML
      <a href="/read/m/c1"><span class="truncate">Chapter 1</span></a>
      <a href="/read/m/c2"><span class="truncate">Start reading</span></a>
      <a href="/read/m/c2"><span class="truncate">Chapter 2</span></a>
    HTML

    links = Html.chapter_links(html)

    assert_equal %w[c1 c2], links.keys
    assert_equal 'Chapter 1', links['c1']['title']
    assert_equal 'Chapter 2', links['c2']['title']
  end

  def test_merge_does_not_downgrade_a_known_title
    seen = { 'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' } }

    Html.merge_chapters!(seen, 'c1' => { 'title' => nil, 'href' => '/read/m/c1' })

    assert_equal 'Chapter 1', seen['c1']['title']
  end

  def test_merge_keeps_titled_entry_over_untitled_one
    seen = { 'c1' => { 'title' => nil, 'href' => '/read/m/c1' } }

    Html.merge_chapters!(seen, 'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' })

    assert_equal 'Chapter 1', seen['c1']['title']
  end

  def test_extracts_reader_image_urls
    html = <<~HTML
      <div data-reader-page><img src="https://cdn/001.webp"></div>
      <div data-reader-page><img src="https://cdn/002.webp"></div>
      <img src="https://cdn/ignored.webp">
    HTML

    assert_equal %w[https://cdn/001.webp https://cdn/002.webp], Html.page_image_urls(html)
  end

  def test_extracts_search_results
    html = <<~HTML
      <div class="text-xs line-clamp-3">Berserk</div>
      <a href="/manga/m1"></a>
      <div class="text-xs line-clamp-3">Vagabond</div>
      <a href="/manga/m2"></a>
    HTML

    assert_equal(
      [{ name: 'Berserk', href: '/manga/m1' }, { name: 'Vagabond', href: '/manga/m2' }],
      Html.search_results(html)
    )
  end

  def test_extracts_manga_page_data
    html = '<script>window.mangaPage = {"mangaPage":{"id":"m1","status":"Ongoing"}};</script>'

    assert_equal 'Ongoing', Html.manga_page_data(html)['status']
    assert_nil Html.manga_page_data('<html></html>')
  end
end
