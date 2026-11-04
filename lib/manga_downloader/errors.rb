# frozen_string_literal: true

module MangaDownloader
  class Error < StandardError; end

  # Raised when a manga chapter list cannot be found on disk.
  class NotFoundError < Error; end
end
