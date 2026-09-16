require 'ferrum'
require_relative 'scraper'
require_relative 'download'
require_relative 'library'

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

def option_a
  with_browser do |page|
    scraper = Scraper.new(page)

    print 'Enter a manga name: '
    name_input = gets.chomp

    result = scraper.search_manga(name_input)
    unless result
      puts 'Manga not found.'
      return
    end

    puts "Scraping chapters for #{result[:name]}..."
    chapters = scraper.get_chapter_list(result[:href])
    scraper.save_chapters(result[:name], chapters)
    puts "Saved #{chapters.size} chapters to #{Scraper.json_path_for(result[:name])}"

    print 'Download now? [y/n] '
    input = gets.chomp.downcase

    Download.new(result[:name], Scraper.json_path_for(result[:name])).init if input == 'y'
  end
end

def option_b
  print 'Enter manga name(s), separated by commas if multiple: '
  input = gets.chomp
  names = input.split(',').map(&:strip).reject(&:empty?)
  return if names.empty?

  with_browser do |page|
    scraper = Scraper.new(page)

    names.each_with_index do |name, idx|
      puts "Searching for \"#{name}\"..."
      result = scraper.search_manga(name)

      unless result
        puts "  Not found: #{name}"
        next
      end

      puts "  Scraping chapters for #{result[:name]}..."
      chapters = scraper.get_chapter_list(result[:href])
      scraper.save_chapters(result[:name], chapters)
      puts "  Saved #{chapters.size} chapters to #{Scraper.json_path_for(result[:name])}"

      next unless idx < names.size - 1

      delay = rand(10..20)
      puts "  Waiting #{delay}s before next manga..."
      sleep(delay)
    end
  end
end

def option_c
  print 'Enter manga name: '
  name = gets.chomp

  with_browser do |page|
    scraper = Scraper.new(page)

    unless Scraper.json_exists?(name)
      puts "No local data found for \"#{name}\", searching the website..."
      result = scraper.search_manga(name)

      unless result
        puts 'Manga not found.'
        return
      end

      chapters = scraper.get_chapter_list(result[:href])
      scraper.save_chapters(result[:name], chapters)
      name = result[:name]
      puts "Saved #{chapters.size} chapters."
    end

    chapters_hash = Scraper.load_json(name)

    print 'Enter chapter(s) to download (e.g. "100-105", "100", or "100,135,151"): '
    range_input = gets.chomp

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
end

def option_d
  downloaded, pending = Library.list_mangas

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
    pending.each { |name| puts "  - #{name}" }
  end

  print "\nDownload one now? Enter manga name (or blank to skip): "
  name = gets.chomp
  return if name.strip.empty?

  unless Scraper.json_exists?(name)
    puts "No data found for \"#{name}\"."
    return
  end

  Download.new(name, Scraper.find_json_path(name)).init
end

def option_e
  json_files = Dir.glob(File.join(Scraper::JSONS_DIR, '*.json')).sort
  if json_files.empty?
    puts 'No saved manga lists found.'
    return
  end

  letters = ('a'..'z').to_a
  mapping = {}

  puts 'Saved manga lists:'
  json_files.each_with_index do |path, idx|
    letter = letters[idx]
    break unless letter

    name = File.basename(path, '.json')
    mapping[letter] = { name: name, path: path }
    puts "[#{letter}] #{name}"
  end

  print 'Enter a letter: '
  input = gets.chomp
  selected = mapping[input]

  unless selected
    puts 'Invalid selection.'
    return
  end

  Download.new(selected[:name], selected[:path]).init
end

loop do
  puts "\n===== Manga Downloader ====="
  puts '[a] manga name to download now'
  puts '[b] add manga to list'
  puts '[c] download specific chapters'
  puts '[d] list mangas'
  puts '[e] download from list'
  puts '[q] quit'
  print 'Choose an option: '

  choice = gets.chomp.downcase

  case choice
  when 'a' then option_a
  when 'b' then option_b
  when 'c' then option_c
  when 'd' then option_d
  when 'e' then option_e
  when 'q' then break
  else puts 'Invalid option.'
  end
end
