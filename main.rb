# frozen_string_literal: true

# Backwards-compatible entry point. Prefer `bin/manga`.
require_relative 'lib/manga_downloader'

exit MangaDownloader::CLI.new(ARGV).run
