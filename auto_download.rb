Encoding.default_external = Encoding::UTF_8

require 'json'
require 'time'
require 'fileutils'
require_relative 'scraper'
require_relative 'download'

# Batch mode used by cron/systemd. Downloads mangas in the order they were
# added, resuming where the previous run stopped and never exceeding the daily
# chapter limit.
class AutoDownload
  DEFAULT_DAILY_LIMIT = 300
  STATE_PATH = File.join(Scraper::JSONS_DIR, '.download_state.json')
  LOCK_PATH = File.join(Scraper::JSONS_DIR, '.download.lock')

  def initialize(limit: DEFAULT_DAILY_LIMIT, only: nil, check_updates: true, out: $stdout)
    @limit = limit.to_i
    @only = only
    @check_updates = check_updates
    @out = out
  end

  def run
    with_lock do
      refresh_updates if @check_updates

      state = load_state
      reset_quota_if_new_day!(state)
      names = sync_queue(state)
      names = names.select { |name| name.casecmp?(@only) } if @only
      save_state(state)

      if names.empty?
        @out.puts 'No mangas in the download queue.'
        return
      end

      remaining = [@limit - state['downloaded_today'].to_i, 0].max

      if remaining.zero?
        @out.puts "Daily limit of #{@limit} chapters already reached. Nothing to do."
        return
      end

      @out.puts "Daily limit: #{@limit} chapters (#{state['downloaded_today']} used, #{remaining} left)"

      downloaded = 0

      names.each do |name|
        break if remaining <= 0

        path = Scraper.find_json_path(name)

        unless path
          @out.puts "Skipping #{name}: no chapter list found."
          next
        end

        @out.puts "Downloading #{name}..."

        count = Download.new(name, path).init(limit: remaining, skip_existing: true)

        next unless count.to_i.positive?

        downloaded += count
        remaining -= count
        state['downloaded_today'] = state['downloaded_today'].to_i + count
        save_state(state)
        @out.puts "  #{count} chapter(s) downloaded. #{remaining} left today."
      end

      @out.puts "Finished: #{downloaded} chapter(s) downloaded today " \
                "(#{state['downloaded_today']}/#{@limit})."
    end
  end

  def status
    state = load_state
    reset_quota_if_new_day!(state)
    names = sync_queue(state)
    save_state(state)
    used = state['downloaded_today'].to_i

    @out.puts "Date: #{state['date']}"
    @out.puts "Used: #{used}/#{@limit} chapters"
    @out.puts "Remaining: #{[@limit - used, 0].max}"
    @out.puts 'Queue (in order added):'

    if names.empty?
      @out.puts '  (empty)'
    else
      names.each_with_index { |name, idx| @out.puts "  #{idx + 1}. #{name}" }
    end
  end

  def reset_quota
    state = load_state
    state['date'] = today
    state['downloaded_today'] = 0
    save_state(state)
    @out.puts "Daily download counter reset. Date: #{state['date']}"
  end

  private

  def refresh_updates
    updates = Scraper.check_updates

    updates.each do |update|
      additions = Scraper.apply_update(update)
      next if additions.empty?

      @out.puts "  #{update[:name]}: #{additions.size} new chapter(s)"
    end
  rescue StandardError => e
    @out.puts "Update check failed: #{e.message}"
  end

  def with_lock
    FileUtils.mkdir_p(Scraper::JSONS_DIR)

    File.open(LOCK_PATH, File::RDWR | File::CREAT, 0o644) do |lock|
      unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        @out.puts 'Another auto-download is already running.'
        return false
      end

      yield
    end

    true
  end

  def load_state
    return {} unless File.exist?(STATE_PATH)

    JSON.parse(File.read(STATE_PATH))
  rescue JSON::ParserError
    {}
  end

  def save_state(state)
    FileUtils.mkdir_p(Scraper::JSONS_DIR)
    tmp = "#{STATE_PATH}.tmp"
    File.write(tmp, JSON.pretty_generate(state))
    File.rename(tmp, STATE_PATH)
  end

  def today
    Time.now.strftime('%Y-%m-%d')
  end

  def reset_quota_if_new_day!(state)
    return if state['date'] == today

    state['date'] = today
    state['downloaded_today'] = 0
  end

  # Keeps previously queued mangas in their original order and appends mangas
  # discovered later, sorted by when their chapter list was first created.
  def sync_queue(state)
    state['queue'] ||= []
    existing = json_names
    queue = state['queue'].select { |name| existing.include?(name) }
    new_names = existing - queue
    new_names.sort_by! { |name| [added_at(Scraper.find_json_path(name)), name] }
    state['queue'] = queue + new_names
  end

  def json_names
    Dir.glob(File.join(Scraper::JSONS_DIR, '*.json')).filter_map do |path|
      name = File.basename(path, '.json')
      next if name.end_with?('_selection_tmp', '_update_tmp')

      name
    end
  end

  # birthtime is not available on every filesystem, so fall back to mtime.
  # Once a manga is in the saved queue its position is kept as-is.
  def added_at(path)
    return Time.at(0) unless path

    begin
      File.stat(path).birthtime
    rescue NotImplementedError, StandardError
      File.mtime(path)
    end
  rescue StandardError
    Time.at(0)
  end
end
