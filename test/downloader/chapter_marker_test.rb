# frozen_string_literal: true

require_relative '../test_helper'

class ChapterMarkerTest < Minitest::Test
  include TestSupport

  Marker = MangaDownloader::Downloader::ChapterMarker

  def test_missing_directory_is_not_complete
    Dir.mktmpdir do |dir|
      refute Marker.complete?(File.join(dir, 'missing'))
    end
  end

  def test_legacy_non_empty_directory_is_complete
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '001.webp'), 'image')

      assert Marker.complete?(dir)
    end
  end

  def test_partial_marker_marks_chapter_incomplete
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '001.webp'), 'image')
      Marker.mark_partial(dir)

      refute Marker.complete?(dir)
      assert Marker.partial?(dir)
    end
  end

  def test_mark_complete_removes_marker
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '001.webp'), 'image')
      Marker.mark_partial(dir)
      Marker.mark_complete(dir)

      assert Marker.complete?(dir)
    end
  end

  def test_empty_directory_is_not_complete
    Dir.mktmpdir do |dir|
      refute Marker.complete?(dir)
    end
  end
end
