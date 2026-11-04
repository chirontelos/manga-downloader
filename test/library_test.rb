# frozen_string_literal: true

require_relative 'test_helper'

class LibraryTest < Minitest::Test
  include TestSupport

  def setup_folder(config, name)
    File.join(config.mangas_dir, MangaDownloader::Naming.path_segment(name))
  end

  def add_chapter_folders(folder, count)
    count.times do |index|
      dir = File.join(folder, format('Chapter %d', index + 1))
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, '001.webp'), 'image')
    end
  end

  def build(config)
    MangaDownloader::Library.new(
      config: config, store: MangaDownloader::Storage::ChapterStore.new(config)
    )
  end

  def test_pending_when_folders_are_missing
    with_config do |config, _dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)
      store.save('Berserk', chapter_list(
                              'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' },
                              'c2' => { 'title' => 'Chapter 2', 'href' => '/read/m/c2' }
                            ))

      downloaded, pending = build(config).list_mangas

      assert_empty downloaded
      assert_equal ['Berserk'], pending
    end
  end

  def test_downloaded_when_every_chapter_folder_is_complete
    with_config do |config, _dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)
      store.save('Berserk', chapter_list(
                              'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' },
                              'c2' => { 'title' => 'Chapter 2', 'href' => '/read/m/c2' }
                            ))
      add_chapter_folders(setup_folder(config, 'Berserk'), 2)

      downloaded, pending = build(config).list_mangas

      assert_equal ['Berserk'], downloaded
      assert_empty pending
    end
  end

  def test_partial_chapter_keeps_manga_pending
    with_config do |config, _dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)
      store.save('Berserk', chapter_list(
                              'c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' },
                              'c2' => { 'title' => 'Chapter 2', 'href' => '/read/m/c2' }
                            ))
      folder = setup_folder(config, 'Berserk')
      add_chapter_folders(folder, 2)
      MangaDownloader::Downloader::ChapterMarker.mark_partial(File.join(folder, 'Chapter 2'))

      downloaded, pending = build(config).list_mangas

      assert_empty downloaded
      assert_equal ['Berserk'], pending
    end
  end
end
