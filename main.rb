class Main
  require 'ferrum'
  require 'nokogiri'
  require 'colorize'
  require 'set'
  require 'fileutils'
  require 'net/http'
  require 'uri'
  require 'json'
  require_relative 'download'

  @@manga_name = ''
  @@manga_path = ''

  def scrape_chapters(page)
    doc = Nokogiri::HTML(page.body)
    found = {}

    doc.css('a[href*="/read/"]').each do |a|
      href = a['href']
      id = href[%r{/read/[^/]+/([^/"]+)}, 1]
      next unless id

      # The chapter title/number sits in a span inside the link
      title_span = a.at_css('span.truncate')
      title = title_span ? title_span.text.strip : nil

      found[id] = { 'title' => title, 'href' => href }
    end
    found
  end

  def find_manga(page)
    print 'Enter a manga name: '
    manga = gets.chomp

    page.go_to("https://atsu.moe/explore?search=#{manga}")
    page.network.wait_for_idle

    doc = Nokogiri::HTML(page.body)

    manga_names = doc.css('div.text-xs.line-clamp-3').map { |d| d.text.strip }
    # takes 'manga/cM0wz', 'manga/Bb7s6'
    manga_hrefs = doc.css('a[href^="/manga/"]').map { |a| a['href'] }

    letters = ('a'..'z').to_a
    # Zip them together sequentially into pairs
    manga_list = manga_names.zip(manga_hrefs, letters).map do |name, href, letter|
      { name: name, href: href, letter: letter }
    end

    puts 'Mangas found:'

    manga_list.each do |manga|
      puts "[#{manga[:letter]}] #{manga[:name]}"
    end

    print 'Enter a letter: '
    input = gets.chomp

    # .first method gives back a string, without it the map would return an array: ["/manga/CM0z3"]
    @@manga_path = manga_list.select { |manga| manga[:letter] == input }.map { |manga| manga[:href] }.first
    @@manga_name = manga
  end

  def get_manga_links(page)
    page.go_to("https://atsu.moe#{@@manga_path}?filter=all")
    page.network.wait_for_idle
    sleep(1.5)

    page.execute(<<~JS)
      const headings = Array.from(document.querySelectorAll('h2'));
      const chaptersHeading = headings.find(h => h.textContent.trim() === 'Chapters');
      if (chaptersHeading) {
        chaptersHeading.scrollIntoView({ block: 'start' });
      }
    JS

    page.network.wait_for_idle
    sleep(0.5)

    seen = {}
    stale_iterations = 0
    max_stale_iterations = 3
    max_total_iterations = 500
    iteration = 0

    loop do
      iteration += 1

      seen.merge!(scrape_chapters(page)) { |_key, old, _new| old } # keep first-seen values

      prev_count = seen.size

      page.execute('window.scrollBy(0, 1500)')
      page.network.wait_for_idle
      sleep(0.4)

      seen.merge!(scrape_chapters(page)) { |_key, old, _new| old }

      new_count = seen.size

      at_bottom = page.evaluate(
        'window.innerHeight + window.scrollY >= document.body.scrollHeight - 10'
      )

      if new_count == prev_count
        stale_iterations += 1
      else
        stale_iterations = 0
      end

      # don't need this printed
      # puts "[iter #{iteration}] total chapters collected: #{new_count} (stale: #{stale_iterations}, at_bottom: #{at_bottom})"

      break if stale_iterations >= max_stale_iterations && at_bottom
      break if iteration >= max_total_iterations
    end

    puts "Finished. Collected #{seen.size} chapters."

    File.write("#{@@manga_name}.json", JSON.pretty_generate(seen))
  end

  def get_manga_name
    @@manga_name
  end
end

browser = Ferrum::Browser.new(
  browser_path: '/usr/local/bin/chromium'
)

page = browser.create_page

main = Main.new

main.find_manga(page)
main.get_manga_links(page)

browser.quit # quit browser from this file

manga_name = main.get_manga_name

print 'Download now?[y/n] '
input = gets.chomp.downcase

if input == 'y'
  download = Download.new(manga_name, "#{manga_name}.json")
  download.init
else
  exit
end
