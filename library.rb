require_relative 'scraper'
require_relative 'download'

module Library
  # Returns [downloaded_names, pending_names]
  def self.list_mangas
    downloaded = []
    pending = []

    Dir.glob(File.join(Scraper::JSONS_DIR, '*.json')).sort.each do |path|
      name = File.basename(path, '.json')

      if downloaded?(name)
        downloaded << name
      else
        pending << name
      end
    end

    [downloaded, pending]
  end

  def self.downloaded?(name)
    folder = File.join(Dir.pwd, Download.sanitize(name))
    return false unless Dir.exist?(folder)

    Dir.children(folder).any? do |sub|
      subpath = File.join(folder, sub)
      Dir.exist?(subpath) && !Dir.empty?(subpath)
    end
  end
end
