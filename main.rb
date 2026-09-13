class Main
  require 'ferrum'
  require 'nokogiri'
  require 'colorize'
  require 'set'
  require 'json'

  # server version
  # allow the manga to be stored in zip and if some user asks for an already downloaded manga sends the zip instead of making all the process again
  # block the loading of images and the like to avoid bandwidth waste https://railsnotes.xyz/blog/ferrum-stealth-browsing
  #
  # v2
  # allow user to pass a list of manga names and download it
  # make browser seems more like a normal browser (https://railsnotes.xyz/blog/ferrum-stealth-browsing and https://akitaonrails.com/en/2026/02/18/web-scraping-in-2026-behind-the-m-akita-chronicles/#the-first-obstacle-spas-and-javascript-rendering (akita stealth mode) )
  # use cellphones as proxy or maybe use 2 oracle servers
  # maybe using catimg to display images, but first check how windows terminal have or if docker can solve everything

  # ask name input from user
  # make browser seems more real by using options
  # search the name input and return the result
  # case 404 or similar warn about it
  # if request sucessfull returns the names of mangas and authors
  # user selects what he wants by the names returned
  # after the selection the program will access the chapters pages, then each chapter page using concurrency or parallelism, and take all the .webp links
  # one dir will be created with the name of manga and inside it the other folders will be created with the number of each chapter or volume to store the images in order.
  # all the .webp images will be downloaded using concurrency, but one chapter at each 6 seconds to avoid stressing the server.
  # print on screen the loading of downloads updating the same line instead of printing new lines
  # see the usage of this: page.network.wait_for_idle(rand(5..14))
  # FIX: take the first values on .json and put as last, this way the order will be correct

  # uncomment here
  puts 'Manga Downloader'.colorize(:green)
  puts

  input = ''

  # uncomment here
  until input == 'exit'
    # maybe use heredoc here
    puts '[a] manga name to download:'
    puts '[b] download from chapter x onwards:'
    puts '[c] list mangas' # divided by downloaded and on waiting
    puts '[d] download chapter'
    puts '[e] download from chapter x onwards'
    puts '[f] add manga to list'
    puts '[i] check new chapters'

    input = gets.chomp
  end

  # uncomment here
  # browser = Ferrum::Browser.new(
  #   browser_path: '/usr/local/bin/chromium'
  # )
  #
  # browser.create_page
  # uncomment here

  # uncomment here
  # page.go_to("https://atsu.moe/explore?search=#{input}")
  # An idle network method ensures a webpage has finished loading its background data
  # before your automation script moves to the next step.
  # In browser automation libraries like Ferrum (used in Ruby), wait_for_idle pauses
  # execution until the network stops sending and receiving data, preventing scripts from
  # failing because elements haven't loaded yet.
  #
  # wait_for_idle returns true if the network goes quiet, or false if it times out.
  # wait_for_idle! does the same but crashes your script with an error (Ferrum::TimeoutError) if the network stays busy too long.
  #
  # Modern websites use JavaScript to load content asynchronously after the main page
  # structure is already there. If your script clicks a button and immediately tries to scrape
  # the next page, it will likely fail because the data hasn't arrived yet. This method forces the
  # script to wait until the network traffic settles.
  # page.network.wait_for_idle
  #
  # uncomment here
  # doc = Nokogiri::HTML(page.body)
  #
  # File.write('searchBody.html', doc)

  # TODO: uncomment later
  # doc = Nokogiri::HTML(File.read('searchBody.html'))
  #
  # manga_names = doc.css('div.text-xs.line-clamp-3').map { |d| d.text.strip }
  # manga_hrefs = doc.css('a[href^="/manga/"]').map { |a| a['href'] }
  #
  # letters = ('a'..'z').to_a
  # # Zip them together sequentially into pairs
  # # zip only accepts two arrays, I need to make an array of hashes with 3 keys/values: letter, name, href
  # manga_list = manga_names.zip(manga_hrefs, letters).map do |name, href, letter|
  #   { name: name, href: href, letter: letter }
  # end
  #
  # puts 'choose one:'
  #
  # manga_list.each do |manga|
  #   puts "[#{manga[:letter]}] #{manga[:name]}"
  # end
  #
  # print 'option: '
  # input = gets.chomp
  #
  # manga_URL = ''
  # manga_list.each do |manga|
  #   manga_URL = manga[:href] if manga[:letter] == input
  # end

  ## working until this line

  # concatenate the root URL with manga URL from above to acess the specific page with the filter=all
  #
  # puts "https://atsu.moe#{manga_URL}?filter=all"
  #
  # page.go_to("https://atsu.moe#{manga_URL}?filter=all")
  # page.network.wait_for_idle
  #
  # doc = Nokogiri::HTML(page.body)
  #
  # File.write('berserk_chapters_page.html', doc)
  #

  # # :NOTE: working
  # def self.scrape_chapters(page)
  #   doc = Nokogiri::HTML(page.body)
  #   found = {}
  #
  #   doc.css('a[href*="/read/"]').each do |a|
  #     href = a['href']
  #     id = href[%r{/read/[^/]+/([^/"]+)}, 1]
  #     next unless id
  #
  #     # The chapter title/number sits in a span inside the link
  #     title_span = a.at_css('span.truncate')
  #     title = title_span ? title_span.text.strip : nil
  #
  #     found[id] = { 'title' => title, 'href' => href }
  #   end
  #
  #   found
  # end
  #
  # browser = Ferrum::Browser.new(headless: true, timeout: 30)
  # page = browser.create_page
  #
  # manga_url = '/manga/v0SEt' # example
  #
  # page.go_to("https://atsu.moe#{manga_url}?filter=all")
  # page.network.wait_for_idle
  # sleep(1)
  #
  # page.execute(<<~JS)
  #   const headings = Array.from(document.querySelectorAll('h2'));
  #   const chaptersHeading = headings.find(h => h.textContent.trim() === 'Chapters');
  #   if (chaptersHeading) {
  #     chaptersHeading.scrollIntoView({ block: 'start' });
  #   }
  # JS
  # page.network.wait_for_idle
  # sleep(0.5)
  #
  # seen = {}
  # stale_iterations = 0
  # max_stale_iterations = 3
  # max_total_iterations = 500
  # iteration = 0
  #
  # loop do
  #   iteration += 1
  #
  #   seen.merge!(scrape_chapters(page)) { |_key, old, _new| old } # keep first-seen values
  #
  #   prev_count = seen.size
  #
  #   page.execute('window.scrollBy(0, 1500)')
  #   page.network.wait_for_idle
  #   sleep(0.4)
  #
  #   seen.merge!(scrape_chapters(page)) { |_key, old, _new| old }
  #
  #   new_count = seen.size
  #
  #   at_bottom = page.evaluate(
  #     'window.innerHeight + window.scrollY >= document.body.scrollHeight - 10'
  #   )
  #
  #   if new_count == prev_count
  #     stale_iterations += 1
  #   else
  #     stale_iterations = 0
  #   end
  #
  #   puts "[iter #{iteration}] total chapters collected: #{new_count} (stale: #{stale_iterations}, at_bottom: #{at_bottom})"
  #
  #   break if stale_iterations >= max_stale_iterations && at_bottom
  #   break if iteration >= max_total_iterations
  # end
  #
  # puts "Finished. Collected #{seen.size} chapters."
  #
  # File.write('boruto_tbv_chapters_page.html', page.body)
  # File.write('boruto_tbv.json', JSON.pretty_generate(seen))
  #
  # browser.quit
  # # NOTE: working until here
  #
  # page.go_to('https://atsu.moe/read/bHwT7/W8dewuB2')
  # page.network.wait_for_idle
  # File.write('gunslinger_chapter_one_page.html', page.body)
end
