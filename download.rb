require 'ferrum'
require 'nokogiri'
require 'net/http'
require 'uri'
require 'fileutils'
require 'json'
require 'time'

class Download
  BASE_URL = 'https://atsu.moe'
  MANGA_DIR = File.join(Dir.pwd, 'mangas')
  ERROR_LOG = File.join(Dir.pwd, 'download_errors.log')
  MAX_DOWNLOAD_THREADS = 6 # parallel image downloads per chapter

  def initialize(manga, chapter_JSON)
    @manga_name = manga
    @chapters_JSON = chapter_JSON
    @log_mutex = Mutex.new
  end

  # Appends errors to a shared log. Every line includes the manga and chapter
  # so failures can be traced even when a download spans hundreds of chapters.
  def log_error(message, chapter: nil)
    entry = "[#{Time.now.iso8601}] manga=\"#{@manga_name}\" chapter=\"#{chapter || '?'}\" #{message}"

    @log_mutex.synchronize do
      File.open(ERROR_LOG, 'a') { |file| file.puts(entry) }
    end
  rescue StandardError
    nil
  end

  def self.sanitize(name)
    name.to_s.strip.downcase.gsub(/\b(?<!\.)[a-z]/) { |match| match.upcase }
  end

  def download_image(url, dest_path, chapter)
    uri = URI.parse(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      http.request(request) do |response|
        if response.is_a?(Net::HTTPSuccess)
          File.open(dest_path, 'wb') do |f|
            response.read_body { |chunk| f.write(chunk) }
          end
          true
        else
          warn "  Failed (#{response.code}): #{url}"
          log_error("image failed (#{response.code}): #{url}", chapter: chapter)
          false
        end
      end
    end
  rescue StandardError => e
    warn "  Error downloading #{url}: #{e.message}"
    log_error("image error: #{url} (#{e.class}: #{e.message})", chapter: chapter)
    false
  end

  def extract_page_urls(page)
    doc = Nokogiri::HTML(page.body)
    doc.css('div[data-reader-page] img').map { |img| img['src'] }.compact
  end

  def chapter_downloaded?(dir)
    Dir.exist?(dir) && !Dir.empty?(dir)
  end

  # Ruby's GC only frees dead objects when it runs, and even then glibc keeps
  # the freed pages in its arenas instead of returning them to the OS. During
  # long downloads that shows up as RAM that keeps climbing after every
  # chapter. Collecting and handing the free pages back keeps usage flat.
  def release_memory
    GC.start(full_mark: true, immediate_sweep: true)
    trim_malloc
  rescue StandardError
    nil
  end

  def trim_malloc
    return unless RUBY_PLATFORM.include?('linux')

    @trim_malloc ||= begin
      require 'fiddle'
      Fiddle::Function.new(
        Fiddle.dlopen(nil)['malloc_trim'],
        [Fiddle::TYPE_LONG],
        Fiddle::TYPE_INT
      )
    rescue StandardError
      nil
    end

    @trim_malloc&.call(0)
  end

  def init(limit: nil, skip_existing: false)
    chapters = JSON.parse(File.read(@chapters_JSON))
    ordered = chapters.to_a.reverse

    if ordered.empty?
      puts 'Nothing to download.'
      return 0
    end

    manga_root = File.join(MANGA_DIR, self.class.sanitize(@manga_name))
    FileUtils.mkdir_p(manga_root)
    processed = 0

    ordered.each_with_index do |(chapter_id, info), idx|
      break if limit && processed >= limit

      title = info['title'] || chapter_id
      href  = info['href']

      unless href
        log_error('chapter has no href, skipping', chapter: title)
        next
      end

      folder_name = self.class.sanitize(title)
      chapter_dir = File.join(manga_root, folder_name)

      next if skip_existing && chapter_downloaded?(chapter_dir)

      FileUtils.mkdir_p(chapter_dir)
      processed += 1

      url = href.start_with?('http') ? href : "#{BASE_URL}#{href}"
      puts "[#{idx + 1}/#{ordered.size}] Loading #{title}"

      # Chromium's renderer keeps growing while pages are loaded and closed
      # (caches, DOM, GPU buffers), and Ferrum itself retains every network
      # exchange for the life of a page. Starting a fresh browser per chapter
      # guarantees all of that memory is released before the next one.
      browser = nil
      page = nil

      begin
        browser = Ferrum::Browser.new(headless: true, timeout: 30)
        page = browser.create_page
        page.go_to(url)
        page.network.wait_for_idle
        sleep(1)

        image_urls = extract_page_urls(page)

        if image_urls.empty?
          warn "  No images found for #{title}, skipping"
          log_error('no images found, skipping chapter', chapter: title)
          next
        end

        print "  Found #{image_urls.size} pages, downloading...\t"

        threads = []
        image_urls.each_with_index do |img_url, page_idx|
          threads << Thread.new do
            begin
              ext = File.extname(URI.parse(img_url).path)
              ext = '.webp' if ext.empty?
              filename = format('%03d%s', page_idx, ext)
              dest = File.join(chapter_dir, filename)
              download_image(img_url, dest, title)
            rescue StandardError => e
              log_error("image error: #{img_url} (#{e.class}: #{e.message})", chapter: title)
            end
          end

          if threads.size >= MAX_DOWNLOAD_THREADS
            threads.each(&:join)
            threads.clear
          end
        end
        threads.each(&:join)

        puts "  Done: #{image_urls.size} images saved"
      rescue StandardError => e
        warn "  Error processing #{title}: #{e.message}"
        log_error("chapter error: #{e.class}: #{e.message}", chapter: title)
      ensure
        begin
          page&.network&.clear(:traffic)
        rescue StandardError
          nil
        end

        begin
          browser&.quit
        rescue StandardError
          nil
        end

        browser = nil
        page = nil
        image_urls = nil
        threads = nil
        release_memory
      end

      next if limit && processed >= limit
      next unless idx < ordered.size - 1

      delay = rand(3..10)
      puts "  Waiting #{delay}s before next chapter..."
      sleep(delay)
    end

    puts 'All done at ' + Time.now.to_s
    processed
  end
end
