# frozen_string_literal: true

module MangaDownloader
  # Single source of truth for turning site manga names into filesystem names.
  # The title-casing rule matches the naming the library was originally built
  # with, so existing folders keep resolving.
  module Naming
    module_function

    def sanitize(name)
      name.to_s.strip.downcase.gsub(/\b(?<!\.)[a-z]/, &:upcase)
    end

    # Portion of a manga name that can safely be used as one path segment.
    def path_segment(name)
      segment = sanitize(name).gsub(%r{[/\\]}, '-').strip
      segment.empty? ? 'Unknown' : segment
    end
  end
end
