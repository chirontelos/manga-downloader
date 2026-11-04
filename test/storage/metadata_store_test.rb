# frozen_string_literal: true

require_relative '../test_helper'

class MetadataStoreTest < Minitest::Test
  include TestSupport

  def test_records_status_and_sources
    with_config do |config, _dir|
      store = MangaDownloader::Storage::MetadataStore.new(config)

      store.record('/manga/m1', status: 'Ongoing', source_ids: %w[s1 s2])

      assert_equal 'Ongoing', store.status('m1')
      assert_equal %w[s1 s2], store.source_ids('m1')
      assert_equal '/manga/m1', store.load['m1']['href']
    end
  end

  def test_source_ids_falls_back_to_single_source_id
    with_config do |config, dir|
      store = MangaDownloader::Storage::MetadataStore.new(config)
      MangaDownloader::AtomicFile.write_json(
        config.metadata_path,
        'm1' => { 'source_id' => 's1' }
      )

      assert_equal %w[s1], store.source_ids('m1')
      assert File.exist?(File.join(dir, 'jsons', '.manga_metadata.json'))
    end
  end

  def test_ignores_corrupt_metadata
    with_config do |config, _dir|
      File.write(config.metadata_path, 'not json')
      store = MangaDownloader::Storage::MetadataStore.new(config)

      assert_empty store.load
      assert_nil store.status('m1')
    end
  end
end
