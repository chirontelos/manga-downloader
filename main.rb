class Main
  require 'ferrum'
  require 'nokogiri'
  require 'colorize'
  require 'set'
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
  #

  # uncomment here
  # puts 'Manga Downloader'.colorize(:green)
  # puts
  #
  # print 'Manga name to download: '
  # input = gets.chomp

  # uncomment here
  # until input == 'exit'
  #   # maybe use heredoc here
  #   print 'Manga name to download: '
  #   input = gets.chomp
  # end

  # uncomment here
  browser = Ferrum::Browser.new(
    browser_path: '/usr/local/bin/chromium'
  )

  browser.create_page

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

  browser = Ferrum::Browser.new(headless: true, timeout: 30)
  page = browser.create_page

  manga_url = '/manga/CM0wz' # example

  page.go_to("https://atsu.moe#{manga_url}?filter=all")
  page.network.wait_for_idle
  sleep(1) # let initial hydration settle

  # Scroll the "Chapters" heading into view first, so subsequent
  # scrollBy steps operate in the right part of the page
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
  max_total_iterations = 500 # safety cap so a bug can't loop forever
  iteration = 0

  loop do
    iteration += 1

    doc = Nokogiri::HTML(page.body)
    doc.css('a[href*="/read/"]').each do |a|
      href = a['href']
      id = href[%r{/read/[^/]+/([^/"]+)}, 1]
      next unless id

      seen[id] ||= href
    end

    prev_count = seen.size

    # scroll the window down
    page.execute('window.scrollBy(0, 1500)')
    page.network.wait_for_idle
    sleep(0.8) # give React time to mount newly-intersected rows

    # re-scrape after scroll to catch chapters that just mounted
    doc = Nokogiri::HTML(page.body)
    doc.css('a[href*="/read/"]').each do |a|
      href = a['href']
      id = href[%r{/read/[^/]+/([^/"]+)}, 1]
      next unless id

      seen[id] ||= href
    end

    new_count = seen.size

    at_bottom = page.evaluate(
      'window.innerHeight + window.scrollY >= document.body.scrollHeight - 10'
    )

    if new_count == prev_count
      stale_iterations += 1
    else
      stale_iterations = 0
    end

    puts "[iter #{iteration}] total chapters collected: #{new_count} (stale: #{stale_iterations}, at_bottom: #{at_bottom})"

    break if stale_iterations >= max_stale_iterations && at_bottom
    break if iteration >= max_total_iterations
  end

  puts "Finished. Collected #{seen.size} chapters."

  # Save final page state and results
  File.write('berserk_chapters_page.html', page.body)

  File.write('chapters.json', JSON.pretty_generate(seen))

  browser.quit

  # mangas = doc.css('a[href^="/manga/"]').map do |node|
  #   {
  #     path: node['href'],
  #     title: node.at_css('p.title')&.text&.strip || node.at_css('img.poster')&.[]('alt')
  #   }
  # end.uniq { |m| m[:path] }
  #
  # mangas.each { |m| puts "#{m[:title]} -> #{m[:path]}" }
  #
  # browser.quit

  #
  # # browser.go_to('https://google.com')
  # browser.go_to('https://atsu.moe/explore?search=berserk')
  # browser.network.wait_for_idle
  # # manga_paths = browser.css('a[href^="/manga/"]').map do |node|
  # #   node.attribute('href')
  # # end.uniq
  # #
  # # puts manga_paths
  #
  # mangas = browser.css('a[href^="/manga/"]').map do |node|
  #   title_node = node.at_css('p.title')
  #   {
  #     path: node.attribute('href'),
  #     title: title_node&.text&.strip
  #   }
  # end.uniq { |m| m[:path] }
  #
  # mangas.each { |m| puts "#{m[:title]} -> #{m[:path]}" }
  #
  # sleep(5)
  #
  # browser.go_to('https://atsu.moe/manga/#{manga_paths[0]}')
  #
  # browser.quit
end
