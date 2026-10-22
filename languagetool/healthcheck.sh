#!/bin/sh
# Health check for Home Assistant's watchdog.
# While n-grams or the fastText model are downloading, LanguageTool (Java) is
# not running yet. Report healthy then, so the watchdog doesn't restart the app
# and throw away a half-finished download. Once Java runs, check the server.
if ! pgrep -x java >/dev/null 2>&1; then
  exit 0
fi
exec /entrypoint healthcheck
