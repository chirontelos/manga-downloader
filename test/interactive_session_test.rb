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
      session, store, out = build_session(config, input: "evangelion\nb\n")
      stub_search(session, duplicate_name_results)
      started = stub_download(session)

      session.send(:download_now)

      assert_equal ['Evangelion: Campus Apocalypse'], started
      assert_equal ['Evangelion: Campus Apocalypse'], store.names
      refute store.exist?('Evangelion')
      assert_match(/Mangas found/, out.string)
      assert_match(/\[b\] Evangelion: Campus Apocalypse/, out.string)
    end
  end

  def test_download_now_accepts_multiple_selections
    with_config do |config, _dir|
      session, store, _out = build_session(config, input: "evangelion\na, b\n")
      stub_search(session, duplicate_name_results)
      started = stub_download(session)

      session.send(:download_now)

      assert_equal ['Evangelion', 'Evangelion: Campus Apocalypse'], started
      assert_equal ['Evangelion', 'Evangelion: Campus Apocalypse'], store.names.sort
    end
  end

  def test_add_manga_saves_multiple_selected_results
    with_config do |config, _dir|
      session, store, out = build_session(config, input: "evangelion\na, b\n")
      stub_search(session, duplicate_name_results)

      session.send(:add_manga)

      assert_equal ['Evangelion', 'Evangelion: Campus Apocalypse'], store.names.sort
      assert_equal 2, out.string.scan('Saved 1 chapters').size
    end
  end

  private

  def build_session(config, input:)
    out = StringIO.new
    store = MangaDownloader::Storage::ChapterStore.new(config)
    ui = MangaDownloader::UI::Console.new(input: StringIO.new(input), output: out)
    session = MangaDownloader::InteractiveSession.new(
      config: config,
      store: store,
      metadata: MangaDownloader::Storage::MetadataStore.new(config),
      api: nil,
      ui: ui,
      reporter: MangaDownloader::Reporter.new(out: out, err: StringIO.new)
    )
    [session, store, out]
  end

  def stub_search(session, results)
    search = FakeSearch.new(results)
    session.define_singleton_method(:with_search) { |&block| block.call(search) }
  end

  def stub_download(session)
    started = []
    session.define_singleton_method(:start_download) { |name, _chapters| started << name }
    started
  end

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
