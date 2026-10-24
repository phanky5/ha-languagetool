#!/bin/sh
# Health check for Home Assistant's watchdog.
# While n-grams or the fastText model are downloading, LanguageTool (Java) is
# not running yet. Report healthy then, so the watchdog doesn't restart the app
# and throw away a half-finished download. Once Java runs, check the server.
if ! pgrep -x java >/dev/null 2>&1; then
  exit 0
fi
# With the secret URL on, LanguageTool listens on an internal port and nginx
# must be running too. run.sh writes the port to this file.
LISTEN_PORT=$(cat /tmp/ha-listen-port 2>/dev/null || echo 8081)
export LISTEN_PORT
if [ "$LISTEN_PORT" != "8081" ] && ! pgrep -x nginx >/dev/null 2>&1; then
  exit 1
fi
# Docker runs health checks as root, so drop privileges here too.
exec setpriv --reuid=783 --regid=783 --clear-groups \
  --inh-caps=-all --bounding-set=-all --no-new-privs \
  /entrypoint healthcheck
