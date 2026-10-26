require_relative 'scraper'
require_relative 'download'

module Library
  # Returns [downloaded_names, pending_names]
  def self.list_mangas
    downloaded = []
    pending = []

    Dir.glob(File.join(Scraper::JSONS_DIR, '*.json')).sort.each do |path|
      name = File.basename(path, '.json')

      if downloaded?(name, path)
        downloaded << name
      else
        pending << name
      end
    end

    [downloaded, pending]
  end

  def self.downloaded?(name, path = Scraper.find_json_path(name))
    return false unless path

    folder = File.join(Download::MANGA_DIR, Download.sanitize(name))
    return false unless Dir.exist?(folder)

    expected = JSON.parse(File.read(path)).size
    return false if expected.zero?

    actual = Dir.children(folder).count do |sub|
      subpath = File.join(folder, sub)
      Dir.exist?(subpath) && !Dir.empty?(subpath)
    end

    actual == expected
  end
end
