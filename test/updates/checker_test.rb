# frozen_string_literal: true

require_relative '../test_helper'

class CheckerTest < Minitest::Test
  include TestSupport

  class FakeApi
    attr_reader :page_calls, :chapter_calls

    def initialize(pages: {}, chapters: {})
      @pages = pages
      @chapters = chapters
      @page_calls = []
      @chapter_calls = []
    end

    def manga_page(id)
      @page_calls << id
      @pages[id]
    end

    def all_chapters(id)
      @chapter_calls << id
      @chapters[id]
    end
  end

  def chapter(id, number, source: 's1')
    {
      'id' => id, 'title' => "Chapter #{number}", 'number' => number,
      'index' => number, 'scanlationMangaId' => source
    }
  end

  def page(chapters, status: 'Ongoing', total: 2)
    { 'status' => status, 'totalChapterCount' => total, 'chapters' => chapters }
  end

  def store_with(config, title, chapter_ids)
    store = MangaDownloader::Storage::ChapterStore.new(config)
    hash = chapter_ids.to_h do |id|
      [id, { 'title' => "Chapter #{id.delete('c')}", 'href' => "/read/m1/#{id}" }]
    end
    store.save(title, chapter_list(hash))
    store
  end

  def build(config, api)
    store = MangaDownloader::Storage::ChapterStore.new(config)
    checker = MangaDownloader::Updates::Checker.new(
      config: config,
      store: store,
      metadata: MangaDownloader::Storage::MetadataStore.new(config),
      api: api,
      reporter: silence_reporter
    )
    [store, checker]
  end

  def test_finds_new_chapters
    with_config do |config, _dir|
      api = FakeApi.new(pages: { 'm1' => page([chapter('c1', 1), chapter('c2', 2)]) })
      store, checker = build(config, api)
      store.save('Berserk', chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/m1/c1' }))

      updates = checker.call

      assert_equal 1, updates.size
      update = updates.first
      assert_equal 'Berserk', update.name
      assert_equal 'm1', update.id
      new_ids = update.new_chapters.map { |chapter| chapter['id'] }
      assert_equal %w[c2], new_ids
    end
  end

  def test_apply_persists_additions_newest_first
    with_config do |config, _dir|
      api = FakeApi.new(pages: { 'm1' => page([chapter('c1', 1), chapter('c2', 2)]) })
      store, checker = build(config, api)
      store.save('Berserk', chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/m1/c1' }))

      additions = checker.apply(checker.call.first)

      assert_equal %w[c2], additions.keys
      assert_equal %w[c2 c1], store.load('Berserk').ids
      assert_empty checker.call
    end
  end

  def test_skips_completed_mangas_without_fetching
    with_config do |config, _dir|
      api = FakeApi.new(pages: { 'm1' => page([chapter('c1', 1)]) })
      store, checker = build(config, api)
      store.save('Berserk', chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/m1/c1' }))
      MangaDownloader::Storage::MetadataStore.new(config).record('/manga/m1', status: 'Completed')

      assert_empty checker.call
      assert_empty api.page_calls
    end
  end

  def test_uses_full_chapter_list_when_local_copy_is_far_behind
    with_config do |config, _dir|
      api = FakeApi.new(
        pages: { 'm1' => page([chapter('c3', 3)], total: 3) },
        chapters: { 'm1' => [chapter('c1', 1), chapter('c2', 2), chapter('c3', 3)] }
      )
      store, checker = build(config, api)
      store.save('Berserk', chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/m1/c1' }))

      updates = checker.call

      new_ids = updates.first.new_chapters.map { |chapter| chapter['id'] }
      assert_equal %w[c3 c2], new_ids
      assert_equal %w[m1], api.chapter_calls
    end
  end
end
