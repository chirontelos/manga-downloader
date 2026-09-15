class Download
  require 'ferrum'
  require 'nokogiri'
  require 'net/http'
  require 'uri'
  require 'fileutils'
  require 'json'

  def initialize(manga, chapter_JSON)
    @manga_name = manga # top-level folder name
    @chapters_JSON = chapter_JSON # produced by your earlier scraping script
  end

  BASE_URL = 'https://atsu.moe'
  MAX_DOWNLOAD_THREADS = 2 # parallel image downloads per chapter

  def sanitize(name)
    name.to_s.strip.gsub(/[^\w-]+/, '_')
  end

  def download_image(url, dest_path)
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
          false
        end
      end
    end
  rescue StandardError => e
    warn "  Error downloading #{url}: #{e.message}"
    false
  end

  def extract_page_urls(page)
    doc = Nokogiri::HTML(page.body)
    doc.css('div[data-reader-page] img').map { |img| img['src'] }.compact
  end

  def init
    chapters = JSON.parse(File.read(@chapters_JSON))
    ordered = chapters.to_a # [[chapter_id, {"title"=>..., "href"=>...}], ...]

    browser = Ferrum::Browser.new(headless: true, timeout: 30)
    page = browser.create_page

    manga_root = File.join(Dir.pwd, @manga_name)
    FileUtils.mkdir_p(manga_root)

    ordered.each_with_index do |(chapter_id, info), idx|
      title = info['title'] || chapter_id
      href  = info['href']
      next unless href

      folder_name = sanitize(title)
      chapter_dir = File.join(manga_root, folder_name)
      FileUtils.mkdir_p(chapter_dir)

      url = href.start_with?('http') ? href : "#{BASE_URL}#{href}"
      puts "[#{idx + 1}/#{ordered.size}] Loading #{title} (#{url})"

      begin
        page.go_to(url)
        page.network.wait_for_idle
        sleep(1) # small buffer for late-mounting images

        image_urls = extract_page_urls(page)

        if image_urls.empty?
          warn "  No images found for #{title}, skipping"
          next
        end

        puts "  Found #{image_urls.size} pages, downloading..."

        threads = []
        image_urls.each_with_index do |img_url, page_idx|
          threads << Thread.new do
            ext = File.extname(URI.parse(img_url).path)
            ext = '.webp' if ext.empty?
            filename = format('%03d%s', page_idx, ext)
            dest = File.join(chapter_dir, filename)
            download_image(img_url, dest)
          end

          if threads.size >= MAX_DOWNLOAD_THREADS
            threads.each(&:join)
            threads.clear
          end
        end
        threads.each(&:join)

        puts "  Done: #{image_urls.size} images saved to #{chapter_dir}"
      rescue StandardError => e
        warn "  Error processing #{title}: #{e.message}"
      end

      next unless idx < ordered.size - 1

      delay = rand(10..20)
      puts "  Waiting #{delay}s before next chapter..."
      sleep(delay)
    end

    browser.quit
    puts 'All done.'
  end
end
