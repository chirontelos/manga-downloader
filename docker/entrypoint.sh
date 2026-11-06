#!/bin/sh
# Run the CLI as the owner of the bind-mounted project so writes to jsons/,
# mangas/ and download_errors.log work regardless of the host user's UID.
set -eu

if [ "$(id -u)" -eq 0 ]; then
  home="${MANGA_HOME:-/app}"
  data="${home}/jsons"
  [ -d "$data" ] || data="$home"
  uid="${MANGA_UID:-$(stat -c %u "$data")}"
  gid="${MANGA_GID:-$(stat -c %g "$data")}"

  exec setpriv --reuid="$uid" --regid="$gid" --clear-groups \
    env HOME=/tmp bundle exec bin/manga "$@"
fi

exec env HOME=/tmp bundle exec bin/manga "$@"
