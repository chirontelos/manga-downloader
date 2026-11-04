# frozen_string_literal: true

module MangaDownloader
  # Extracting a stable manga id from the several places it can appear.
  module MangaId
    INPUT_URL = %r{\Ahttps?://(?:www\.)?atsu\.moe/manga/([A-Za-z0-9_-]+)/?\z}i
    FROM_HREF = %r{/manga/([^/?#]+)}
    FROM_READ = %r{\A/read/([^/]+)/}

    module_function

    def from_input(input)
      input.to_s.strip[INPUT_URL, 1]
    end

    def from_href(href)
      href.to_s[FROM_HREF, 1]
    end

    def from_read_href(href)
      href.to_s[FROM_READ, 1]
    end

    # Local chapter lists don't store the manga id, but every chapter href
    # contains it: /read/<manga_id>/<chapter_id>.
    def from_chapter_list(chapter_list)
      chapter_list.each do |chapter|
        id = from_read_href(chapter.href)
        return id if id
      end
      nil
    end

    def from_local_hash(hash)
      hash.each_value do |info|
        id = from_read_href(info['href'])
        return id if id
      end
      nil
    end
  end
end
