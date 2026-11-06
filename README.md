# Manga Downloader

A command-line tool that searches [atsu.moe](https://atsu.moe), saves manga
chapter lists as JSON, and downloads chapter pages as images. It supports an
interactive menu, unattended daily downloads with a quota, automatic
new-chapter checks, and resumable downloads.

Docker is the recommended way to run it: the image includes Ruby and Chromium,
so there is nothing else to install.

## Features

- Search by manga name or URL and choose from matching results
- Interactive menu or fully unattended mode
- Daily chapter quota with automatic reset
- Automatic new-chapter detection before downloads
- Resumable downloads: completed pages are skipped
- Interrupted chapters are marked `.partial` and retried on the next run
- Configurable concurrency, timeouts and retries
- Failed images are logged only after all retries fail
- One connection-safe lock prevents two auto-downloads from running at once

## Quick start with Docker (recommended)

Requirements: Docker with the Compose plugin.

```sh
git clone <repository-url>
cd manga_downloader

docker compose build
docker compose run --rm manga
```

The last command opens the interactive menu:

```
===== Manga Downloader =====
[a] manga name or link to download now
[b] add manga to list
[c] list mangas and download
[d] check for updates
[q] quit
```

### Menu options

| Option | Description |
| --- | --- |
| `a` | Search by name/link, choose one or more results, then download now |
| `b` | Search and add one or more manga to the list without downloading |
| `c` | Show downloaded/pending manga and optionally download one |
| `d` | Check all saved manga for new chapters and download selected ones |
| `q` | Quit |

When multiple search results are shown, enter one or more letters separated by
commas, for example `a, c`.

The typical workflow is:

1. Run the menu and use `b` to add the manga you want.
2. Run `docker compose run --rm manga --auto` whenever you want to download.
3. Or schedule that command with cron for daily updates.

### Docker commands

```sh
# Build/rebuild the image
docker compose build

# Interactive menu
docker compose run --rm manga

# Download pending chapters without prompting
docker compose run --rm manga --auto

# Daily cap for this run
docker compose run --rm manga --auto --limit 50

# Only one manga (exact name, case-insensitive)
docker compose run --rm manga --auto --manga "Vagabond"

# Skip the new-chapter check
docker compose run --rm manga --auto --no-update

# Status and quota
docker compose run --rm manga --status
docker compose run --rm manga --reset-quota
```

Do not use `docker compose up` for normal use; it attaches to the interactive
menu. Use `docker compose run --rm` as shown above.

### Updating

```sh
git pull
docker compose build
```

Your `jsons/` and `mangas/` directories are not touched by the rebuild.

### Data and permissions

The project directory is mounted into the container, so your library stays on
the host:

```
jsons/<manga>.json                 saved chapter lists
jsons/.download_state.json         daily counter and queue
mangas/<manga>/<chapter>/001.webp  downloaded pages
download_errors.log                unresolved image failures
```

The container automatically runs as the owner of the mounted `jsons/`
directory, so files are not created as root. To force an identity:

```sh
MANGA_UID=$(id -u) MANGA_GID=$(id -g) docker compose run --rm manga --auto
```

If an earlier run created root-owned files, fix them once:

```sh
sudo chown -R "$(id -u):$(id -g)" jsons mangas download_errors.log
```

### Scheduling daily downloads

Example crontab entry:

```cron
0 3 * * * cd /path/to/manga_downloader && docker compose run --rm manga --auto --limit 50 >> cron.log 2>&1
```

The daily quota resets automatically when the date changes. `--limit` is the
total number of chapters allowed for the day, not a per-run increment.

If cron cannot find `docker`, use its absolute path (for example
`/usr/bin/docker`).

## Native installation (without Docker)

Requirements:

- Ruby >= 3.2 (developed and tested on Ruby 4.0.1)
- Chromium or Google Chrome, used by Ferrum
- Bundler

On Debian/Ubuntu:

```sh
sudo apt update
sudo apt install -y ruby-full chromium

cd /path/to/manga_downloader
gem install bundler
bundle install

bin/manga
```

Install only the runtime gems if you do not need the test suite:

```sh
bundle config set --local without 'development test'
bundle install
```

If Chromium is not detected automatically, point to it explicitly:

```sh
CHROMIUM_PATH=/usr/bin/chromium bin/manga
```

The `mise.toml` file pins the development Ruby version if you use
[mise](https://mise.jdx.dev/):

```sh
mise install
bundle install
bin/manga
```

`main.rb` is kept as a compatibility entry point, but `bin/manga` is preferred.

## Command-line options

```
Usage: bin/manga [options]

Run without options for the interactive menu.

    --auto          Download queued mangas without prompting (for cron)
    --limit N       Chapters to download today (default: MANGA_DAILY_LIMIT)
    --manga NAME    Only process this manga
    --no-update     Do not check for new chapters before downloading
    --status        Show the daily counter and download queue
    --reset-quota   Reset today's chapter counter
    -h, --help      Show help
```

`--auto` processes saved manga only; add manga through the menu first.

## Chapter selection

When downloading from the menu, you can enter:

| Input | Meaning |
| --- | --- |
| `all` | Every chapter |
| `100` | Exactly chapter 100 |
| `100-105` | Every chapter numbered 100 through 105 |
| `1-5` | Includes decimal chapters such as 1.1, 1.2, … 1.7 |
| `1.1-1.5` | Decimal range |
| `1,3,10` | Exact chapters 1, 3 and 10 |
| `5-1` | Same as `1-5` |

Chapters are always downloaded oldest-first.

## Configuration

All settings are environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MANGA_HOME` | project root | Where `jsons/`, `mangas/` and logs live |
| `MANGA_BASE_URL` | `https://atsu.moe` | Site base URL |
| `CHROMIUM_PATH` | auto-detected | Chromium/Chrome executable |
| `MANGA_DAILY_LIMIT` | `300` | Default chapters per day in auto mode |
| `MANGA_IMAGE_THREADS` | `10` | Parallel image downloads per chapter (capped at 20) |
| `MANGA_HTTP_OPEN_TIMEOUT` | `60` | TCP connect timeout, seconds |
| `MANGA_HTTP_READ_TIMEOUT` | `60` | Per-read timeout, seconds |
| `MANGA_HTTP_RETRIES` | `3` | Extra attempts per failed image |
| `MANGA_HTTP_RETRY_DELAY` | `2` | Seconds between image retries |
| `MANGA_PAGE_TIMEOUT` | `60` | Browser page-load timeout, seconds |
| `MANGA_PROTOCOL_TIMEOUT` | `120` | Browser/CDP response timeout, seconds |
| `MANGA_CHAPTER_RETRIES` | `1` | Extra browser attempts after a chapter timeout |
| `MANGA_UID` / `MANGA_GID` | detected | Docker only: run as this user |

Docker uses `MANGA_PAGE_TIMEOUT=90` and `MANGA_PROTOCOL_TIMEOUT=180` by default.
Override them the same way:

```sh
MANGA_IMAGE_THREADS=3 docker compose run --rm manga --auto
MANGA_PAGE_TIMEOUT=180 MANGA_PROTOCOL_TIMEOUT=300 docker compose run --rm manga --auto
```

### Download behaviour

- Images are fetched with at most `MANGA_IMAGE_THREADS` concurrent requests
  (10 by default, never more than 20).
- Failed images are retried, then written to `download_errors.log` only if every
  attempt fails.
- Existing non-empty pages are skipped, so rerunning resumes a chapter.
- A chapter is only counted against the daily quota when it completes fully.

## Troubleshooting

### Browser/page timeout

```
Ferrum::TimeoutError: Timed out waiting for response
```

Raise the browser timeouts:

```sh
MANGA_PAGE_TIMEOUT=180 MANGA_PROTOCOL_TIMEOUT=300 bin/manga --auto
```

With Docker, add the same variables before `docker compose run`.

### CDN connection timeout

```
Failed to open TCP connection ... user specified timeout
```

This is the TCP connect timeout. Try fewer parallel downloads and a longer
timeout:

```sh
MANGA_IMAGE_THREADS=3 MANGA_HTTP_OPEN_TIMEOUT=90 bin/manga --auto
```

### Docker permission denied

```
Permission denied @ rb_sysopen - /app/jsons/.download.lock
```

The entrypoint normally handles this by running as the project owner. If the
folders are root-owned from an earlier run:

```sh
sudo chown -R "$(id -u):$(id -g)" jsons mangas download_errors.log
```

### Docker build warning about commit information

```
current commit information was not captured by the build
```

This is a harmless BuildKit provenance warning when `.git` is excluded from the
build context. It does not affect the image.

## Development

```sh
bundle install

bundle exec rake          # RuboCop + tests
bundle exec rake test
bundle exec rubocop
```

CI runs the same checks (`.github/workflows/ci.yml`).

### Project layout

```
bin/manga                          executable entry point
lib/manga_downloader/
  config.rb                        paths, timings, limits
  cli.rb                           option parsing and dispatch
  interactive_session.rb           interactive menu
  auto_download.rb                 quota/queue/locking for cron
  downloader/                      image fetching and chapter orchestration
  domain/                          pure chapter/order/selection logic
  storage/                         chapter list and metadata persistence
  scraping/                        Chromium and HTML adapters
  api/                             site JSON API client
  updates/                         new-chapter detection
  library.rb                       downloaded vs pending view
  http_transport.rb                HTTP timeouts, retries and streaming
  reporter.rb                      console output + rotating error log
test/                              Minitest suite
```

## Notes

- Chapter lists are stored newest-first; downloads run oldest-first.
- A lock file prevents two auto-downloads from running at the same time.
- Use this tool for personal use and respect the site's terms of service and
  your local copyright laws.
