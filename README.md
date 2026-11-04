# Manga Downloader

Scrapes manga chapter lists from [atsu.moe](https://atsu.moe), stores them as
JSON, and downloads chapter pages as images. It can run interactively or as a
cron/systemd job with a daily chapter quota.

## Requirements

- Ruby >= 3.2 (developed on 4.0.1, see `mise.toml`)
- Chromium/Chrome for Ferrum (`CHROMIUM_PATH` to override detection)

```sh
bundle install
```

## Usage

```sh
bin/manga                # interactive menu
bin/manga --help         # all options
bin/manga --status       # daily counter + download queue
bin/manga --auto         # cron mode, no prompts
bin/manga --auto --limit 50 --manga "Vagabond"
bin/manga --reset-quota
```

`main.rb` is kept as a compatibility shim; `bin/manga` is the preferred entry
point.

### Docker

The image bundles Ruby and Chromium, so only Docker is required on the host.
Runtime data is bind-mounted from the project, so downloads and saved chapter
lists stay in the usual `jsons/` and `mangas/` folders.

```sh
docker compose build

# Interactive menu (add/search/download)
docker compose run --rm manga

# Unattended download, for cron
docker compose run --rm manga --auto --limit 50
docker compose run --rm manga --auto --manga "Vagabond"
docker compose run --rm manga --status
```

The container runs as UID/GID `1000` by default. If your user has a different
ID, set it once in a `.env` file next to `docker-compose.yml`:

```sh
MANGA_UID=$(id -u)
MANGA_GID=$(id -g)
```

Then run the commands above normally. A daily cron entry can look like:

```cron
0 3 * * * cd /home/newm/projects/mangaDownloader && docker compose run --rm manga --auto --limit 50 >> cron.log 2>&1
```

Override timings/limits with environment variables, for example:

```sh
MANGA_IMAGE_THREADS=3 docker compose run --rm manga --auto
```

### Configuration

Everything tunable lives in `MangaDownloader::Config` and can be overridden with
environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MANGA_HOME` | project root | Where `jsons/`, `mangas/` and logs live |
| `MANGA_BASE_URL` | `https://atsu.moe` | Site base URL |
| `CHROMIUM_PATH` | `/usr/local/bin/chromium` if present | Browser executable |
| `MANGA_HTTP_OPEN_TIMEOUT` | `60` | TCP connect timeout, seconds |
| `MANGA_HTTP_READ_TIMEOUT` | `60` | Per-read timeout, seconds |
| `MANGA_HTTP_RETRIES` | `3` | Extra attempts per image before logging a failure |
| `MANGA_HTTP_RETRY_DELAY` | `2` | Seconds to wait between image retries |
| `MANGA_IMAGE_THREADS` | `6` | Parallel image downloads per chapter (capped at 10) |
| `MANGA_DAILY_LIMIT` | `300` | Chapters per day in auto mode |

Remaining delays/limits are constructor arguments of `Config` (see
`lib/manga_downloader/config.rb`).

### CDN connection timeouts

`Failed to open TCP connection ... user specified timeout` means the **connect**
timeout (`MANGA_HTTP_OPEN_TIMEOUT`) fired. The defaults (60s connect, 60s read)
match what Net::HTTP used before timeouts were configured explicitly. If it
still happens frequently, make the download gentler:

```sh
MANGA_IMAGE_THREADS=3 bin/manga --auto
```

and raise `MANGA_HTTP_OPEN_TIMEOUT` further if the CDN is slow to accept
connections.

Images are fetched with at most `MANGA_IMAGE_THREADS` (6 by default, never more
than 10) concurrent requests. A failed image is retried up to
`MANGA_HTTP_RETRIES` times with a fixed delay; only failures that survive every
attempt are written to `download_errors.log`. Interrupted chapters are marked
`.partial` and retried on the next run, and pages already on disk are skipped.

## Layout

```
bin/manga                          executable
lib/manga_downloader/
  config.rb                        paths, timings, limits
  atomic_file.rb                   crash-safe writes
  naming.rb                        name → filename rules
  manga_id.rb                      extracting manga ids from URLs/hrefs
  http_transport.rb                HTTP with timeouts/retries/streaming
  reporter.rb                      console output + rotating error log
  ui.rb                            the only stdin reader
  domain/                          pure logic (chapters, ordering, selection)
  storage/                         chapter-list and metadata persistence
  api/                             site JSON API client
  scraping/                        browser + HTML adapters
  downloader/                      image fetching and chapter orchestration
  updates/                         new-chapter detection
  library.rb                       downloaded vs pending view
  auto_download.rb                 quota/queue/locking for cron
  interactive_session.rb           interactive menu
  cli.rb                           option parsing and dispatch
test/                              minitest suite
```

Dependency direction: `cli` → interactive/auto → domain + storage + scraping +
downloader. Domain objects never touch stdin, stdout, files or Ferrum.

## Development

```sh
bundle exec rake          # rubocop + tests
bundle exec rake test
bundle exec rubocop
```

CI runs the same commands (`.github/workflows/ci.yml`).

## Notes

- Downloads are resumable: existing non-empty images are skipped and a
  `.partial` marker keeps interrupted chapters from counting as complete.
- Only fully downloaded chapters consume the daily quota.
- Running two auto-downloads at once is prevented with `flock`.
- Chapter lists are saved newest-first; downloads run oldest-first.
