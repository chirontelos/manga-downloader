require 'nokogiri'
require 'json'
require 'fileutils'
require 'uri'
require 'net/http'
require 'time'

class Scraper
  JSONS_DIR = File.join(Dir.pwd, 'jsons')
  METADATA_PATH = File.join(JSONS_DIR, '.manga_metadata.json')
  API_BASE = 'https://atsu.moe/api'
  TRACKED_STATUSES = %w[ongoing hiatus].freeze

  def initialize(page)
    @page = page
    FileUtils.mkdir_p(JSONS_DIR)
  end

  def self.sanitize_filename(name)
    name.to_s.strip.downcase.gsub(/\b(?<!\.)[a-z]/) { |match| match.upcase }
  end

  def self.json_path_for(name)
    File.join(JSONS_DIR, "#{sanitize_filename(name)}.json")
  end

  def self.find_json_path(name)
    target = sanitize_filename(name).downcase

    Dir.glob(File.join(JSONS_DIR, '*.json')).find do |path|
      File.basename(path, '.json').downcase == target
    end
  end

  def self.json_exists?(name)
    !find_json_path(name).nil?
  end

  # Labels used to let the user select from a list: a..z first, then ab..az,
  # ba..bz, ca..cz, and so on when there are more than 26 entries.
  def self.selection_labels(count)
    letters = ('a'..'z').to_a
    labels = letters.dup

    letters.each do |first|
      letters.each do |second|
        next if first == 'a' && second == 'a'

        labels << "#{first}#{second}"
      end
    end

    labels.first(count)
  end

  def self.load_json(name)
    path = find_json_path(name)
    raise "No JSON found for \"#{name}\"" unless path

    JSON.parse(File.read(path))
  end

  def self.load_metadata
    return {} unless File.exist?(METADATA_PATH)

    JSON.parse(File.read(METADATA_PATH))
  rescue JSON::ParserError
    {}
  end

  def self.save_metadata(manga_href, status: nil, source_id: nil, source_ids: nil)
    id = manga_href.to_s[%r{/manga/([^/?#]+)}, 1]
    return unless id

    metadata = load_metadata
    entry = metadata[id] ||= { 'href' => "/manga/#{id}" }
    entry['status'] = status if status
    entry['source_id'] = source_id if source_id
    entry['source_ids'] = source_ids if source_ids
    entry['checked_at'] = Time.now.utc.iso8601
    File.write(METADATA_PATH, JSON.pretty_generate(metadata))
  end

  def self.trackable_status?(status)
    TRACKED_STATUSES.include?(status.to_s.downcase)
  end

  def self.http_get_json(url)
    uri = URI.parse(url)
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'Mozilla/5.0'

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    warn "  Error fetching #{url}: #{e.message}"
    nil
  end

  def self.fetch_manga_page_data(id)
    http_get_json("#{API_BASE}/manga/page?id=#{URI.encode_www_form_component(id)}")&.dig('mangaPage')
  end

  def self.fetch_all_chapters(id)
    http_get_json("#{API_BASE}/manga/allChapters?mangaId=#{URI.encode_www_form_component(id)}")&.dig('chapters')
  end

  def self.manga_id_from_chapters(chapters)
    chapters.each_value do |info|
      href = info['href']
      next unless href

      id = href[%r{\A/read/([^/]+)/}, 1]
      return id if id
    end
    nil
  end

  # Checks saved mangas for new chapters using the site's API. Only Ongoing
  # and Hiatus mangas are checked, and only the manga page data (which already
  # includes the latest chapters) is fetched when possible.
  def self.check_updates
    metadata = load_metadata
    updates = []

    Dir.glob(File.join(JSONS_DIR, '*.json')).sort.each do |path|
      name = File.basename(path, '.json')
      next if name.end_with?('_selection_tmp', '_update_tmp')

      chapters = JSON.parse(File.read(path))
      id = manga_id_from_chapters(chapters)
      next unless id

      status = metadata.dig(id, 'status')
      source_ids = Array(metadata.dig(id, 'source_ids') || metadata.dig(id, 'source_id')).compact
      next if status && !trackable_status?(status)

      page = fetch_manga_page_data(id)
      next unless page

      status = page['status']
      save_metadata("/manga/#{id}", status: status)
      next unless trackable_status?(status)

      latest = page['chapters'] || []

      if source_ids.empty?
        source_ids = latest.select { |chapter| chapters.key?(chapter['id']) }
                           .map { |chapter| chapter['scanlationMangaId'] }
                           .compact
                           .uniq
        save_metadata("/manga/#{id}", source_ids: source_ids) unless source_ids.empty?
      end

      latest = latest.select { |chapter| source_ids.include?(chapter['scanlationMangaId']) } unless source_ids.empty?
      overlap = latest.any? { |chapter| chapters.key?(chapter['id']) }

      # When none of the latest chapters are saved yet, the local copy is far
      # behind; fetch the full list so no new chapter is missed.
      candidates = if !overlap && page['totalChapterCount'].to_i > chapters.size
                     full = fetch_all_chapters(id)
                     if full && !source_ids.empty?
                       full = full.select { |chapter| source_ids.include?(chapter['scanlationMangaId']) }
                     end
                     full || latest
                   else
                     latest
                   end

      max_saved_number = candidates.filter_map do |chapter|
        chapter['number'] if chapters.key?(chapter['id'])
      end.max

      new_chapters = if max_saved_number
                       candidates.select { |chapter| chapter['number'] && chapter['number'] > max_saved_number }
                     else
                       candidates.reject { |chapter| chapters.key?(chapter['id']) }
                     end

      new_chapters = new_chapters.sort_by { |chapter| [-(chapter['number'] || 0), -(chapter['index'] || 0)] }
      next if new_chapters.empty?

      updates << {
        name: name,
        json_path: path,
        id: id,
        href: "/manga/#{id}",
        status: status,
        new_chapters: new_chapters,
        existing_chapters: chapters
      }
    end

    updates
  end

  def self.apply_update(update)
    additions = update[:new_chapters].each_with_object({}) do |chapter, hash|
      next if update[:existing_chapters].key?(chapter['id'])

      hash[chapter['id']] = {
        'title' => chapter['title'],
        'href' => "/read/#{update[:id]}/#{chapter['id']}"
      }
    end

    return {} if additions.empty?

    File.write(
      update[:json_path],
      JSON.pretty_generate(additions.merge(update[:existing_chapters]))
    )
    additions
  end

  # Extracts a manga id from a full URL like
  # "https://atsu.moe/manga/CM0wz". Returns nil for normal manga names.
  def self.manga_id_from_input(input)
    match = input.to_s.strip.match(%r{\Ahttps?://(?:www\.)?atsu\.moe/manga/([A-Za-z0-9_-]+)/?\z}i)
    match && match[1]
  end

  # Resolves user input that references a manga by URL. Returns a result hash
  # like search_manga does, or nil if the input isn't a valid manga link (so
  # callers can fall back to a name search).
  def resolve_manga_link(input)
    id = self.class.manga_id_from_input(input)
    return nil unless id

    href = "/manga/#{id}"
    @page.go_to("https://atsu.moe#{href}")
    @page.network.wait_for_idle
    sleep(1)

    title = Nokogiri::HTML(@page.body).at_css('title')&.text&.strip
    return nil if title.nil? || title.empty? || title == 'Atsumaru'

    chapters = get_chapter_list(href)
    return nil if chapters.empty?

    { name: title, href: href, chapters: chapters }
  rescue StandardError
    nil
  end

  # Searches the site for a manga by name. Returns a single result hash, an
  # array of result hashes when +multi+ is true, or nil if nothing was found /
  # selected.
  def search_manga(name, interactive: true, multi: false)
    @page.go_to("https://atsu.moe/explore?search=#{URI.encode_www_form_component(name)}")
    @page.network.wait_for_idle
    sleep(1)

    doc = Nokogiri::HTML(@page.body)
    manga_names = doc.css('div.text-xs.line-clamp-3').map { |d| d.text.strip }
    manga_hrefs = doc.css('a[href^="/manga/"]').map { |a| a['href'] }

    labels = self.class.selection_labels(manga_names.size)
    manga_list = manga_names.zip(manga_hrefs, labels).map do |mname, href, letter|
      { name: mname, href: href, letter: letter }
    end

    return nil if manga_list.empty?

    disambiguate_duplicate_names(manga_list)

    if manga_list.size == 1
      single = manga_list.first.slice(:name, :href, :chapters)
      return multi ? [single] : single
    end

    unless interactive
      return multi ? manga_list.map { |m| m.slice(:name, :href, :chapters) } : manga_list.first.slice(:name, :href, :chapters)
    end

    puts "Mangas found for \"#{name}\":"
    manga_list.each { |m| puts "[#{m[:letter]}] #{m[:name]}" }

    if multi
      print 'Enter letter(s), separated by commas if multiple: '
      input = gets.chomp

      selected = input.split(',').map(&:strip).filter_map do |letter|
        manga_list.find { |m| m[:letter] == letter }
      end
      return nil if selected.empty?

      selected.map { |m| m.slice(:name, :href, :chapters) }
    else
      print 'Enter a letter: '
      input = gets.chomp

      selected = manga_list.find { |m| m[:letter] == input }
      return nil unless selected

      selected.slice(:name, :href, :chapters)
    end
  end

  # Mangas can share the exact same name on the site. When that happens,
  # append the chapter count to each one's name so they don't overwrite each
  # other's JSON file or download folder.
  def disambiguate_duplicate_names(manga_list)
    manga_list.group_by { |m| m[:name] }.each_value do |group|
      next if group.size < 2

      group.each do |manga|
        chapters = get_chapter_list(manga[:href])
        manga[:chapters] = chapters
        manga[:name] = "#{manga[:name]} #{chapters.size}"
      end
    end
  end

  def scrape_chapter_links_from_page
    doc = Nokogiri::HTML(@page.body)
    found = {}

    doc.css('a[href*="/read/"]').each do |a|
      href = a['href']
      id = href[%r{/read/[^/]+/([^/"]+)}, 1]
      next unless id

      title_span = a.at_css('span.truncate')
      title = title_span ? title_span.text.strip : nil

      # The "Start reading" shortcut points at the first chapter (e.g.
      # "Prologue 1"), so it shares that chapter's id/href. Ignore it so the
      # real title can be captured later.
      next if title == 'Start reading'

      existing = found[id]

      # Some rows expose the same href twice (one without a title); keep a
      # titled entry over an untitled one instead of overwriting it.
      found[id] = { 'title' => title, 'href' => href } if existing.nil? || existing['title'].nil?
    end

    found
  end

  # Merges newly scraped chapters into +seen+ without downgrading an already
  # known title to nil.
  def merge_chapters!(seen, new_entries)
    new_entries.each do |id, info|
      existing = seen[id]
      seen[id] = info if existing.nil? || (existing['title'].nil? && info['title'])
    end
  end

  def extract_manga_page_data(html)
    script = Nokogiri::HTML(html).xpath('//script[contains(text(), "window.mangaPage =")]').first
    return nil unless script

    json = script.text[/window\.mangaPage = (\{.*\});\s*\z/m, 1]
    return nil unless json

    JSON.parse(json)['mangaPage']
  rescue JSON::ParserError
    nil
  end

  # Stores the manga status while the page is already loaded, so update checks
  # can skip Completed mangas without fetching them again.
  def record_manga_metadata(manga_href)
    data = extract_manga_page_data(@page.body)
    @last_manga_page_data = data
    return unless data && data['status']

    id = data['id'] || manga_href[%r{/manga/([^/?#]+)}, 1]
    return unless id

    self.class.save_metadata("/manga/#{id}", status: data['status'])
  rescue StandardError
    nil
  end

  def source_summary(page_data, groups)
    names = (page_data && page_data['scanlators'] || []).to_h { |source| [source['id'], source['name']] }
    all_numbers = groups.values.flatten.filter_map { |chapter| chapter['number'] }
    global_min, global_max = all_numbers.minmax
    total = page_data && page_data['totalChapterCount'].to_f

    groups.map do |source_id, chapters|
      numbers = chapters.filter_map { |chapter| chapter['number'] }
      full = if total.positive?
               numbers.max && numbers.max.to_f >= total && chapters.size >= total
             else
               global_min && global_max && numbers.min && numbers.max &&
                 numbers.min <= global_min && numbers.max >= global_max
             end

      {
        id: source_id,
        name: names[source_id] || source_id,
        chapters: chapters,
        count: chapters.size,
        full: full
      }
    end
  end

  def ask_source(candidates)
    labels = self.class.selection_labels(candidates.size)
    candidates.each_with_index { |source, idx| source[:label] = labels[idx] }

    puts 'Multiple sources available:'
    candidates.each do |source|
      puts "[#{source[:label]}] #{source[:name]} (#{source[:count]} chapters)"
    end

    loop do
      print 'Choose a source: '
      input = gets&.chomp&.strip&.downcase
      return candidates.first if input.nil?

      chosen = candidates.find { |source| source[:label] == input }
      return chosen if chosen

      puts 'Invalid selection.'
    end
  end

  def choose_sources(sources)
    full_sources = sources.select { |source| source[:full] }

    if full_sources.size == 1
      chosen = full_sources.first
      puts "Using source #{chosen[:name]} (has the entire manga)."
      return [chosen]
    end

    return [ask_source(full_sources)] if full_sources.size > 1

    primary = sources.max_by { |source| source[:count] }
    [primary, *sources.reject { |source| source.equal?(primary) }.sort_by { |source| -source[:count] }]
  end

  def chapter_key(chapter)
    chapter['number'].nil? ? "id:#{chapter['id']}" : chapter['number'].to_f
  end

  def merge_source_chapters(sources)
    primary = sources.first
    by_number = {}

    primary[:chapters].each do |chapter|
      by_number[chapter_key(chapter)] ||= chapter
    end

    used_sources = [primary]

    sources.drop(1).each do |source|
      added = false
      source[:chapters].each do |chapter|
        key = chapter_key(chapter)
        next if by_number.key?(key)

        by_number[key] = chapter
        added = true
      end
      used_sources << source if added
    end

    ordered = by_number.values.sort_by do |chapter|
      [-(chapter['number'] || 0), -(chapter['index'] || 0)]
    end
    [ordered, used_sources]
  end

  # Keeps chapters from a single source. If only one source covers the entire
  # manga it is picked automatically; otherwise the user chooses. When no
  # source covers everything, the one with the most chapters is used and the
  # missing chapters are filled from the others.
  def chapters_for_source(manga_href, chapters)
    id = manga_href[%r{/manga/([^/?#]+)}, 1]
    return chapters unless id

    page_data = @last_manga_page_data || self.class.fetch_manga_page_data(id)
    scanlators = page_data && page_data['scanlators'] || []
    return chapters if scanlators.size < 2

    all_chapters = self.class.fetch_all_chapters(id)
    return chapters unless all_chapters && !all_chapters.empty?

    groups = all_chapters.group_by { |chapter| chapter['scanlationMangaId'] }
    return chapters if groups.size < 2

    sources = source_summary(page_data, groups)
    chosen_sources = choose_sources(sources)
    merged_chapters, used_sources = merge_source_chapters(chosen_sources)

    if used_sources.size > 1
      names = used_sources.map { |source| source[:name] }.join(', ')
      puts "No single source covers the entire manga. Using #{names}."
    end

    self.class.save_metadata("/manga/#{id}", source_ids: used_sources.map { |source| source[:id] })

    merged_chapters.each_with_object({}) do |chapter, result|
      result[chapter['id']] = {
        'title' => chapter['title'],
        'href' => "/read/#{id}/#{chapter['id']}"
      }
    end
  end

  # Scrolls through the (virtualized) chapters list, collecting every entry.
  def get_chapter_list(manga_href)
    @page.go_to("https://atsu.moe#{manga_href}?filter=all")
    @page.network.wait_for_idle
    sleep(1.5)
    record_manga_metadata(manga_href)

    @page.execute(<<~JS)
      const headings = Array.from(document.querySelectorAll('h2'));
      const chaptersHeading = headings.find(h => h.textContent.trim() === 'Chapters');
      if (chaptersHeading) {
        chaptersHeading.scrollIntoView({ block: 'start' });
      }
    JS
    @page.network.wait_for_idle
    sleep(0.5)

    seen = {}
    stale_iterations = 0
    max_stale_iterations = 3
    max_total_iterations = 500
    iteration = 0

    loop do
      iteration += 1
      merge_chapters!(seen, scrape_chapter_links_from_page)
      prev_count = seen.size

      # Smaller step so virtualized rows aren't skipped.
      @page.execute('window.scrollBy(0, 800)')
      @page.network.wait_for_idle
      sleep(0.6)

      merge_chapters!(seen, scrape_chapter_links_from_page)
      new_count = seen.size

      at_bottom = @page.evaluate(
        'window.innerHeight + window.scrollY >= document.body.scrollHeight - 10'
      )

      stale_iterations = new_count == prev_count ? stale_iterations + 1 : 0

      break if stale_iterations >= max_stale_iterations && at_bottom
      break if iteration >= max_total_iterations
    end

    settle_at_bottom(seen)
    chapters = fix_chapter_order(seen)
    chapters_for_source(manga_href, chapters)
  end

  # The last rows (e.g. "Prologue 1") often render late once the bottom is
  # reached. Keep scrolling to the bottom and re-scraping with longer waits
  # until nothing new shows up.
  def settle_at_bottom(seen, max_attempts: 8)
    quiet = 0

    max_attempts.times do
      before = seen.size

      # Virtualized lists often only (re)render their last rows when the
      # viewport moves, so scroll up a bit first, then back to the very
      # bottom, scraping at each position.
      @page.execute('window.scrollBy(0, -700)')
      sleep(1.0)
      merge_chapters!(seen, scrape_chapter_links_from_page)

      @page.execute('window.scrollTo(0, document.body.scrollHeight)')
      @page.network.wait_for_idle
      sleep(2.0)
      merge_chapters!(seen, scrape_chapter_links_from_page)

      quiet = seen.size == before ? quiet + 1 : 0

      break if quiet >= 3
    end
  end

  # Repositions misplaced/null-titled entries (typically the earliest
  # chapter/volume) into their correct numeric spot in the descending list.
  # Ties (e.g. "Chapter 3" and "Prologue 3") keep the site's original order.
  def fix_chapter_order(chapters_hash)
    entries = chapters_hash.map { |id, info| [id, info] }

    numbered = entries.each_with_index.map do |(id, info), idx|
      title = info['title']
      num = title ? title[/(\d+(?:\.\d+)?)/, 1] : nil
      [id, info, num&.to_f, idx]
    end

    known_numbers = numbered.map { |_, _, num, _| num }.compact
    return chapters_hash if known_numbers.empty?

    max_num = known_numbers.max
    min_num = known_numbers.min

    missing = ((min_num.to_i)..(max_num.to_i)).to_a - known_numbers.map(&:to_i)
    missing.sort!

    numbered = numbered.map do |id, info, num, idx|
      if num.nil?
        inferred = missing.shift || (min_num - 1)
        [id, info, inferred.to_f, idx]
      else
        [id, info, num, idx]
      end
    end

    numbered
      .sort_by { |_, _, num, idx| [-num, idx] }
      .each_with_object({}) { |(id, info, _, _), hash| hash[id] = info }
  end

  def save_chapters(name, chapters_hash)
    File.write(self.class.json_path_for(name), JSON.pretty_generate(chapters_hash))
  end
end
