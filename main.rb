Encoding.default_external = Encoding::UTF_8

require 'ferrum'
require 'optparse'
require_relative 'scraper'
require_relative 'download'
require_relative 'library'
require_relative 'auto_download'

def with_browser
  browser = Ferrum::Browser.new(browser_path: '/usr/local/bin/chromium')
  page = browser.create_page
  yield page
ensure
  browser.quit
end

def parse_chapter_selection(input, chapters_hash)
  by_number = {}

  chapters_hash.each do |id, info|
    title = info['title']
    next unless title

    num = title[/(\d+(?:\.\d+)?)/, 1]
    next unless num

    by_number[num.to_f] = [id, info]
  end

  selected_numbers = []

  input.split(',').each do |part|
    part = part.strip
    if part.include?('-')
      from, to = part.split('-').map { |n| n.strip.to_f }
      from, to = [from, to].minmax
      selected_numbers.concat((from.to_i..to.to_i).map(&:to_f))
    else
      selected_numbers << part.to_f
    end
  end

  selected_numbers.uniq.sort.reverse.each_with_object({}) do |num, hash|
    pair = by_number[num]
    next unless pair

    id, info = pair
    hash[id] = info
  end
end

def download_chapters(name, json_path, chapters_hash)
  print 'Enter chapter(s) to download (e.g. "100-105", "100", "100,135,151", or "all"): '
  range_input = gets.chomp

  if range_input.strip.downcase == 'all'
    Download.new(name, json_path).init
    return
  end

  selection = parse_chapter_selection(range_input, chapters_hash)

  if selection.empty?
    puts 'No matching chapters found.'
    return
  end

  temp_json = Scraper.json_path_for("#{name}_selection_tmp")
  File.write(temp_json, JSON.pretty_generate(selection))

  Download.new(name, temp_json).init

  File.delete(temp_json) if File.exist?(temp_json)
end

def option_a
  print 'Enter manga name or link: '
  input = gets.chomp

  with_browser do |page|
    scraper = Scraper.new(page)

    if Scraper.json_exists?(input)
      chapters_hash = Scraper.load_json(input)
      download_chapters(input, Scraper.find_json_path(input), chapters_hash)
      return
    end

    linked = scraper.resolve_manga_link(input)

    if linked
      name = linked[:name]
      path = Scraper.find_json_path(name)

      unless path
        scraper.save_chapters(name, linked[:chapters])
        puts "Saved #{linked[:chapters].size} chapters to #{Scraper.json_path_for(name)}"
        path = Scraper.find_json_path(name)
      end

      chapters_hash = Scraper.load_json(name)
      download_chapters(name, path, chapters_hash)
      return
    end

    name = input

    puts "No local data found for \"#{name}\", searching the website..."
    results = scraper.search_manga(name, multi: true)

    unless results
      puts 'Manga not found.'
      return
    end

    saved = results.map do |result|
      chapters = result[:chapters] || scraper.get_chapter_list(result[:href])
      scraper.save_chapters(result[:name], chapters)
      puts "Saved #{chapters.size} chapters to #{Scraper.json_path_for(result[:name])}"

      { name: result[:name], path: Scraper.find_json_path(result[:name]) }
    end

    labels = Scraper.selection_labels(saved.size)
    mapping = {}

    puts "\nSaved manga lists:"
    saved.each_with_index do |entry, idx|
      letter = labels[idx]
      next unless letter

      mapping[letter] = entry
      puts "[#{letter}] #{entry[:name]}"
    end

    print "\nSelect a manga to download now (or blank to skip): "
    input = gets.chomp.strip.downcase
    return if input.empty?

    selected = mapping[input]

    unless selected
      puts 'Invalid selection.'
      return
    end

    chapters_hash = Scraper.load_json(selected[:name])
    download_chapters(selected[:name], selected[:path], chapters_hash)
  end
end

def option_b
  print 'Enter manga name(s) or link(s), separated by commas if multiple: '
  input = gets.chomp
  names = input.split(',').map(&:strip).reject(&:empty?)
  return if names.empty?

  with_browser do |page|
    scraper = Scraper.new(page)

    names.each_with_index do |name, idx|
      puts "Searching for \"#{name}\"..."
      result = scraper.resolve_manga_link(name) || scraper.search_manga(name)

      unless result
        puts "  Not found: #{name}"
        next
      end

      puts "  Scraping chapters for #{result[:name]}..."
      chapters = result[:chapters] || scraper.get_chapter_list(result[:href])
      scraper.save_chapters(result[:name], chapters)
      puts "  Saved #{chapters.size} chapters to #{Scraper.json_path_for(result[:name])}"

      next unless idx < names.size - 1

      delay = rand(10..20)
      puts "  Waiting #{delay}s before next manga..."
      sleep(delay)
    end
  end
end

def option_d
  downloaded, pending = Library.list_mangas

  if downloaded.empty? && pending.empty?
    puts 'No saved manga lists found.'
    return
  end

  labels = Scraper.selection_labels(pending.size)
  mapping = {}

  puts "\nDownloaded mangas:"
  if downloaded.empty?
    puts '  (none)'
  else
    downloaded.each { |name| puts "  - #{name}" }
  end

  puts "\nAdded but not downloaded yet:"
  if pending.empty?
    puts '  (none)'
  else
    pending.each_with_index do |name, idx|
      letter = labels[idx]
      mapping[letter] = name if letter
      puts "  [#{letter || '?'}] #{name}"
    end
  end

  print "\nDownload one now? Enter letter (or blank to skip): "
  input = gets.chomp.strip.downcase
  return if input.empty?

  name = mapping[input]

  unless name
    puts "Invalid option: #{input}"
    return
  end

  path = Scraper.find_json_path(name)

  unless path
    puts "No data found for \"#{name}\"."
    return
  end

  chapters_hash = Scraper.load_json(name)
  download_chapters(name, path, chapters_hash)
end

def option_u
  puts 'Checking for updates...'
  updates = Scraper.check_updates

  if updates.empty?
    puts 'No updates found.'
    return
  end

  updates.each { |update| update[:additions] = Scraper.apply_update(update) }

  labels = Scraper.selection_labels(updates.size)
  mapping = {}

  puts "\nMangas with new chapters:"
  updates.each_with_index do |update, idx|
    letter = labels[idx]
    next unless letter

    mapping[letter] = update
    puts "[#{letter}] #{update[:name]} (+#{update[:new_chapters].size} new chapter(s), #{update[:status]})"
  end

  print "\nDownload new chapter(s)? Enter letter(s), separated by commas (or blank to skip): "
  input = gets.chomp.strip.downcase
  return if input.empty?

  selected = input.split(',').map(&:strip).filter_map { |letter| mapping[letter] }

  if selected.empty?
    puts 'No matching selection.'
    return
  end

  selected.each_with_index do |update, idx|
    additions = update[:additions]
    next if additions.nil? || additions.empty?

    temp_json = Scraper.json_path_for("#{update[:name]}_update_tmp")
    File.write(temp_json, JSON.pretty_generate(additions))

    begin
      Download.new(update[:name], temp_json).init
    ensure
      File.delete(temp_json) if File.exist?(temp_json)
    end

    next unless idx < selected.size - 1

    delay = rand(10..20)
    puts "Waiting #{delay}s before next manga..."
    sleep(delay)
  end
end

def interactive
  loop do
    puts "\n===== Manga Downloader ====="
    puts '[a] manga name or link to download now'
    puts '[b] add manga to list'
    puts '[d] list mangas and download'
    puts '[u] check for updates'
    puts '[q] quit'
    print 'Choose an option: '

    choice = gets.chomp.downcase

    case choice
    when 'a' then option_a
    when 'b' then option_b
    when 'd' then option_d
    when 'u' then option_u
    when 'q' then break
    else puts 'Invalid option.'
    end
  end
end

def cli(argv)
  options = {}

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby main.rb [options]'
    opts.separator ''
    opts.separator 'Run without options for the interactive menu.'
    opts.separator ''
    opts.on('--auto', 'Download queued mangas without prompting (for cron)') do
      options[:auto] = true
    end
    opts.on('--limit N', Integer, 'Chapters to download today (default: 300)') do |limit|
      options[:limit] = limit
    end
    opts.on('--manga NAME', 'Only process this manga') do |name|
      options[:manga] = name
    end
    opts.on('--no-update', 'Do not check for new chapters before downloading') do
      options[:check_updates] = false
    end
    opts.on('--status', 'Show the daily counter and download queue') do
      options[:status] = true
    end
    opts.on('--reset-quota', "Reset today's chapter counter") do
      options[:reset] = true
    end
    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end

  begin
    parser.parse!(argv)
  rescue OptionParser::ParseError => e
    warn e.message
    warn parser
    exit 1
  end

  limit = options[:limit] || AutoDownload::DEFAULT_DAILY_LIMIT
  auto = AutoDownload.new(limit: limit)

  if options[:status]
    auto.status
  elsif options[:reset]
    auto.reset_quota
  elsif options[:auto]
    auto = AutoDownload.new(
      limit: limit,
      only: options[:manga],
      check_updates: options.fetch(:check_updates, true)
    )
    auto.run
  else
    puts parser
    exit 1
  end
end

ARGV.empty? ? interactive : cli(ARGV)
