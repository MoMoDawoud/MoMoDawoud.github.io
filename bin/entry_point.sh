#!/bin/bash
set -euo pipefail

echo "Entry point script running"

CONFIG_FILE="_config.yml"
JEKYLL_PID=""

manage_gemfile_lock() {
  git config --global --add safe.directory '*'
  if command -v git >/dev/null 2>&1 && [ -f Gemfile.lock ]; then
    if git ls-files --error-unmatch Gemfile.lock >/dev/null 2>&1; then
      echo "Gemfile.lock is tracked by git, keeping it intact"
      git restore Gemfile.lock 2>/dev/null || true
    else
      echo "Gemfile.lock is not tracked by git, removing it"
      rm -f Gemfile.lock
    fi
  fi
}

start_jekyll() {
  manage_gemfile_lock
  bundle exec jekyll serve --watch --port=8080 --host=0.0.0.0 --livereload --verbose --trace --force_polling &
  JEKYLL_PID=$!
  echo "Jekyll started with PID $JEKYLL_PID"
}

stop_jekyll() {
  if [ -n "${JEKYLL_PID:-}" ]; then
    # be tolerant if it already exited/restarted
    if kill -0 "$JEKYLL_PID" 2>/dev/null; then
      # prefer TERM; KILL only if needed
      kill "$JEKYLL_PID" 2>/dev/null || true
      # don't let set -e break on wait
      wait "$JEKYLL_PID" 2>/dev/null || true
      echo "Jekyll PID $JEKYLL_PID stopped"
    fi
  fi
}

trap 'stop_jekyll' EXIT

start_jekyll

# Optional: verify inotifywait exists; fallback to just sleeping
if ! command -v inotifywait >/dev/null 2>&1; then
  echo "inotifywait not found; skipping manual restart loop (Jekyll still auto-reloads)."
  wait "$JEKYLL_PID"
  exit 0
fi

# Watch for real writes/moves/deletes to avoid noisy events
while inotifywait -q -e close_write,move,create,delete --format '%e %w%f' "$CONFIG_FILE"; do
  echo "Change detected to $CONFIG_FILE, restarting Jekyll"
  stop_jekyll
  start_jekyll
done
