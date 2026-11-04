# frozen_string_literal: true

require 'fileutils'
require 'time'

module MangaDownloader
  # Console output plus an append-only error log. Keeping this behind one
  # object makes the domain code free of direct `puts`/`warn` calls.
  class Reporter
    def initialize(out: $stdout, err: $stderr, error_log_path: nil, max_log_bytes: 1_048_576)
      @out = out
      @err = err
      @error_log_path = error_log_path
      @max_log_bytes = max_log_bytes
      @mutex = Mutex.new
    end

    def info(message)
      @out.puts(message)
    end

    def progress(message)
      @out.print(message)
      @out.flush
    end

    def warn(message)
      @err.puts(message)
    end

    # Logs a failure to the rotating error log and echoes it to the console.
    def error(message, manga: nil, chapter: nil)
      warn("  #{message}")
      append_to_log(message, manga: manga, chapter: chapter)
    end

    private

    def append_to_log(message, manga:, chapter:)
      return unless @error_log_path

      entry = "[#{Time.now.iso8601}] manga=\"#{manga || '?'}\" " \
              "chapter=\"#{chapter || '?'}\" #{message}"

      @mutex.synchronize do
        rotate_log_if_needed
        FileUtils.mkdir_p(File.dirname(@error_log_path))
        File.open(@error_log_path, 'a') { |file| file.puts(entry) }
      end
    rescue StandardError
      nil
    end

    def rotate_log_if_needed
      path = @error_log_path
      return unless File.exist?(path) && File.size(path) > @max_log_bytes

      FileUtils.mv(path, "#{path}.1")
    end
  end
end
