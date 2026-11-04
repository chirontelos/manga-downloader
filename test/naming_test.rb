# frozen_string_literal: true

require_relative 'test_helper'

class NamingTest < Minitest::Test
  include TestSupport

  def test_sanitize_matches_existing_library_names
    assert_equal 'Berserk', MangaDownloader::Naming.sanitize('berserk')
    assert_equal 'Tomo-Chan Is A Girl!', MangaDownloader::Naming.sanitize('tomo-chan is a girl!')
    assert_equal 'Gambling Apocalypse Kaiji 13', MangaDownloader::Naming.sanitize('Gambling Apocalypse Kaiji 13')
  end

  def test_path_segment_removes_slashes
    assert_equal 'A-B', MangaDownloader::Naming.path_segment('a/b')
    assert_equal 'Unknown', MangaDownloader::Naming.path_segment('   ')
  end

  def test_atomic_file_round_trip
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'nested', 'file.json')
      MangaDownloader::AtomicFile.write_json(path, 'a' => 1)

      assert_equal({ 'a' => 1 }, MangaDownloader::AtomicFile.read_json(path))
      assert_equal({}, MangaDownloader::AtomicFile.read_json(File.join(dir, 'missing.json'), fallback: {}))
    end
  end
end
