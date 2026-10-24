#!/bin/sh
# Starts the built app image like Home Assistant would and checks that
# LanguageTool finds mistakes in English and German, with and without the
# secret URL. Usage: smoke-test.sh <image>
set -eu

IMAGE=$1
KEY=smoke-test-key-0123456789abcdefghijklmnop
WORK=$(mktemp -d)

log() { echo "[smoke-test] $*"; }

cleanup() {
  docker rm -f lt-smoke >/dev/null 2>&1 || true
  # Data files belong to the container's user, so remove them from inside.
  docker run --rm --entrypoint sh -v "$WORK:/w" "$IMAGE" -c 'rm -rf /w/*' >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# Starts the app with the given options.json content.
start_app() {
  docker rm -f lt-smoke >/dev/null 2>&1 || true
  mkdir -p "$WORK/data"
  echo "$1" >"$WORK/data/options.json"
  docker run -d --name lt-smoke -p 8081:8081 -v "$WORK/data:/data" "$IMAGE" >/dev/null
}

# Waits until LanguageTool answers at the given base URL.
wait_ready() {
  i=0
  until curl -fsS --max-time 5 "$1/languages" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 90 ] || ! docker ps -q -f name=lt-smoke | grep -q .; then
      log "FAIL: LanguageTool didn't start. App log:"
      docker logs lt-smoke 2>&1 | tail -50
      exit 1
    fi
    sleep 5
  done
  log "LanguageTool answers at $1"
}

# Checks a text and expects a match from the given rule.
expect_rule() {
  base=$1 lang=$2 text=$3 rule=$4
  result=$(curl -fsS --max-time 30 "$base/check" \
    --data-urlencode "language=$lang" --data-urlencode "text=$text")
  if echo "$result" | jq -e --arg r "$rule" '[.matches[].rule.id] | index($r)' >/dev/null; then
    log "OK: '$text' ($lang) -> $rule"
  else
    log "FAIL: '$text' ($lang) didn't find $rule. Answer: $result"
    exit 1
  fi
}

check_both_languages() {
  expect_rule "$1" en-US "This is a tset." MORFOLOGIK_RULE_EN_US
  expect_rule "$1" de-DE "Das ist ein Tset." GERMAN_SPELLER_RULE
}

log "Test 1: default options (fastText on, no n-grams)"
start_app '{"ngrams":[],"fasttext":true,"java_xms":"512m","java_xmx":"1536m","speed_up_checks":true,"secret_url":false,"secret_key":""}'
wait_ready http://localhost:8081/v2
check_both_languages http://localhost:8081/v2
# fastText detects the language when the client sends language=auto.
detected=$(curl -fsS --max-time 30 http://localhost:8081/v2/check \
  --data-urlencode "language=auto" \
  --data-urlencode "text=Das ist ein ganz normaler deutscher Satz über das Wetter heute." |
  jq -r '.language.detectedLanguage.code')
case "$detected" in
  de*) log "OK: language detection says $detected" ;;
  *) log "FAIL: language detection says '$detected', expected German"; exit 1 ;;
esac
log "Waiting for the container health check."
i=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' lt-smoke)" = "healthy" ]; do
  i=$((i + 1))
  if [ "$i" -ge 40 ]; then log "FAIL: container never became healthy"; exit 1; fi
  sleep 5
done
log "OK: container is healthy"

log "Test 2: secret URL"
start_app "{\"ngrams\":[],\"fasttext\":false,\"java_xms\":\"512m\",\"java_xmx\":\"1536m\",\"speed_up_checks\":true,\"secret_url\":true,\"secret_key\":\"$KEY\"}"
wait_ready "http://localhost:8081/$KEY/v2"
check_both_languages "http://localhost:8081/$KEY/v2"
if curl -fsS --max-time 10 http://localhost:8081/v2/languages >/dev/null 2>&1; then
  log "FAIL: LanguageTool answered without the secret key"
  exit 1
fi
log "OK: no answer without the secret key"

docker logs lt-smoke 2>&1 | tail -15
log "All tests passed."
