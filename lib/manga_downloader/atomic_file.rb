# frozen_string_literal: true

require 'fileutils'
require 'json'

module MangaDownloader
  # Writes files via a temporary sibling and an atomic rename, so a crash or
  # a full disk can never leave a half-written chapter list or state file.
  module AtomicFile
    module_function

    def write(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      File.open(tmp, 'w') do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(tmp, path)
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    end

    def write_json(path, data)
      write(path, JSON.pretty_generate(data))
    end

    def read_json(path, fallback: nil)
      return fallback unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      fallback
    end
  end
end
