require 'nokogiri'
require 'json'
require 'fileutils'
require 'uri'

class Scraper
  JSONS_DIR = File.join(Dir.pwd, 'jsons')

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

  def self.load_json(name)
    path = find_json_path(name)
    raise "No JSON found for \"#{name}\"" unless path

    JSON.parse(File.read(path))
  end

  # Searches the site for a manga by name.
  # Returns { name:, href: } or nil if nothing was found / selected.
  def search_manga(name, interactive: true)
    @page.go_to("https://atsu.moe/explore?search=#{URI.encode_www_form_component(name)}")
    @page.network.wait_for_idle
    sleep(1)

    doc = Nokogiri::HTML(@page.body)
    manga_names = doc.css('div.text-xs.line-clamp-3').map { |d| d.text.strip }
    manga_hrefs = doc.css('a[href^="/manga/"]').map { |a| a['href'] }

    letters = ('a'..'z').to_a
    manga_list = manga_names.zip(manga_hrefs, letters).map do |mname, href, letter|
      { name: mname, href: href, letter: letter }
    end

    return nil if manga_list.empty?
    return { name: manga_list.first[:name], href: manga_list.first[:href] } if manga_list.size == 1

    return { name: manga_list.first[:name], href: manga_list.first[:href] } unless interactive

    puts "Mangas found for \"#{name}\":"
    manga_list.each { |m| puts "[#{m[:letter]}] #{m[:name]}" }
    print 'Enter a letter: '
    input = gets.chomp

    selected = manga_list.find { |m| m[:letter] == input }
    return nil unless selected

    { name: selected[:name], href: selected[:href] }
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

      found[id] = { 'title' => title, 'href' => href }
    end

    found
  end

  # Scrolls through the (virtualized) chapters list, collecting every entry.
  def get_chapter_list(manga_href)
    @page.go_to("https://atsu.moe#{manga_href}?filter=all")
    @page.network.wait_for_idle
    sleep(1.5)

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
      seen.merge!(scrape_chapter_links_from_page) { |_key, old, _new| old }
      prev_count = seen.size

      @page.execute('window.scrollBy(0, 1500)')
      @page.network.wait_for_idle
      sleep(0.4)

      seen.merge!(scrape_chapter_links_from_page) { |_key, old, _new| old }
      new_count = seen.size

      at_bottom = @page.evaluate(
        'window.innerHeight + window.scrollY >= document.body.scrollHeight - 10'
      )

      stale_iterations = new_count == prev_count ? stale_iterations + 1 : 0

      break if stale_iterations >= max_stale_iterations && at_bottom
      break if iteration >= max_total_iterations
    end

    fix_chapter_order(seen)
  end

  # Repositions misplaced/null-titled entries (typically the earliest
  # chapter/volume) into their correct numeric spot in the descending list.
  def fix_chapter_order(chapters_hash)
    entries = chapters_hash.map { |id, info| [id, info] }

    numbered = entries.map do |id, info|
      title = info['title']
      num = title ? title[/(\d+(?:\.\d+)?)/, 1] : nil
      [id, info, num&.to_f]
    end

    known_numbers = numbered.map { |_, _, num| num }.compact
    return chapters_hash if known_numbers.empty?

    max_num = known_numbers.max
    min_num = known_numbers.min

    missing = ((min_num.to_i)..(max_num.to_i)).to_a - known_numbers.map(&:to_i)
    missing.sort!

    numbered = numbered.map do |id, info, num|
      if num.nil?
        inferred = missing.shift || (min_num - 1)
        [id, info, inferred.to_f]
      else
        [id, info, num]
      end
    end

    numbered
      .sort_by { |_, _, num| -num }
      .each_with_object({}) { |(id, info, _), hash| hash[id] = info }
  end

  def save_chapters(name, chapters_hash)
    File.write(self.class.json_path_for(name), JSON.pretty_generate(chapters_hash))
  end
end
