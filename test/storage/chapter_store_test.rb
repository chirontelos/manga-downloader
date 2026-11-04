# frozen_string_literal: true

require_relative '../test_helper'

class ChapterStoreTest < Minitest::Test
  include TestSupport

  def setup
    @store = nil
  end

  def test_save_find_and_load_round_trip
    with_config do |config, _dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)
      list = chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' })

      store.save('Berserk', list)

      assert store.exist?('berserk')
      assert store.exist?('Berserk')
      assert_equal %w[c1], store.load('BERSERK').ids
      assert_equal store.path_for('Berserk'), store.find_path('berserk')
    end
  end

  def test_load_missing_raises_not_found
    with_config do |config, _dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)

      assert_raises(MangaDownloader::NotFoundError) { store.load('Nope') }
    end
  end

  def test_names_excludes_temporary_files
    with_config do |config, _dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)
      list = chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' })
      store.save('Berserk', list)
      MangaDownloader::AtomicFile.write_json(store.path_for('Berserk_selection_tmp'), {})

      assert_equal ['Berserk'], store.names
    end
  end

  def test_writes_leave_no_temporary_files
    with_config do |config, dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)
      store.save('Berserk', chapter_list('c1' => { 'title' => 'Chapter 1', 'href' => '/read/m/c1' }))

      leftovers = Dir.glob(File.join(dir, 'jsons', '*.tmp'))
      assert_empty leftovers
    end
  end

  def test_corrupt_file_load_raises
    with_config do |config, _dir|
      store = MangaDownloader::Storage::ChapterStore.new(config)
      File.write(store.path_for('Broken'), '{not json')

      assert_raises(MangaDownloader::NotFoundError) { store.load('Broken') }
    end
  end
end
