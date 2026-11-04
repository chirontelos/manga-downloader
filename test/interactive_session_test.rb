# frozen_string_literal: true

require_relative 'test_helper'

class InteractiveSessionTest < Minitest::Test
  include TestSupport

  class FakeSearch
    def initialize(results)
      @results = results
    end

    def resolve_link(_input) = nil

    def search(_name) = @results
  end

  def test_download_now_saves_only_the_selected_search_result
    with_config do |config, _dir|
      results = duplicate_name_results
      store = MangaDownloader::Storage::ChapterStore.new(config)
      out = StringIO.new
      ui = MangaDownloader::UI::Console.new(input: StringIO.new("evangelion\nb\n"), output: out)
      session = MangaDownloader::InteractiveSession.new(
        config: config,
        store: store,
        metadata: MangaDownloader::Storage::MetadataStore.new(config),
        api: nil,
        ui: ui,
        reporter: MangaDownloader::Reporter.new(out: out, err: StringIO.new)
      )
      search = FakeSearch.new(results)
      session.define_singleton_method(:with_search) { |&block| block.call(search) }

      started = []
      session.define_singleton_method(:start_download) { |name, _chapters| started << name }
      session.send(:download_now)

      assert_equal ['Evangelion: Campus Apocalypse'], started
      assert_equal ['Evangelion: Campus Apocalypse'], store.names
      refute store.exist?('Evangelion')
      assert_match(/Mangas found/, out.string)
      assert_match(/\[b\] Evangelion: Campus Apocalypse/, out.string)
    end
  end

  private

  def duplicate_name_results
    [
      {
        name: 'Evangelion',
        href: '/manga/evangelion',
        chapters: chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/e/c1' })
      },
      {
        name: 'Evangelion: Campus Apocalypse',
        href: '/manga/campus',
        chapters: chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/c/c1' })
      }
    ]
  end
end
