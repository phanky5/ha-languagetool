#!/bin/sh
# Only used when the secret URL is on. The image's entrypoint always starts
# LanguageTool with --public, which makes it listen on all network
# interfaces. Without it, LanguageTool only listens on localhost, so it can
# be reached only through nginx and the secret key.
for arg do
  shift
  [ "$arg" = "--public" ] && continue
  set -- "$@" "$arg"
done
exec /opt/java/customjre/bin/java "$@"
