# syntax=docker/dockerfile:1

FROM ruby:4.0.1-slim

ENV LANG=C.UTF-8 \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    MANGA_HOME=/app \
    CHROMIUM_PATH=/usr/bin/chromium \
    FERRUM_CHROME_DOCKERIZE=true \
    HOME=/tmp

# Chromium plus the fonts it needs for the chapter pages. Ferrum drives it
# directly, so no X server or VNC is required.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        chromium \
        fonts-liberation \
        build-essential \
        libffi-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 manga

WORKDIR /app

# Install runtime gems first so this layer is cached when only code changes.
COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' \
    && bundle install

COPY . .

RUN mkdir -p /app/jsons /app/mangas \
    && chown -R manga:manga /app

USER manga

# `docker compose run --rm manga` opens the menu; append `--auto` for cron.
ENTRYPOINT ["bundle", "exec", "bin/manga"]
