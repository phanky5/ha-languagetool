#!/bin/sh
# Start script for the LanguageTool Home Assistant app.
# Reads the app options, removes n-gram data for deselected languages,
# downloads n-grams (resumable), then drops root privileges and hands over
# to the original meyay/languagetool entrypoint.
set -eu

OPTIONS_FILE=/data/options.json
NGRAM_DIR=/data/ngrams
FASTTEXT_DIR=/data/fasttext
ALL_LANGS="en de es fr nl"
LT_UID=783
LT_GID=783

# Download attempts per language before giving up for this start.
MAX_ATTEMPTS=10

log() { echo "[ha-languagetool] $*"; }

# Read one option, falling back to a default if the file or key is missing.
option() {
  if [ -f "$OPTIONS_FILE" ]; then
    # Not using "//" here, because it would treat false as missing.
    value=$(jq -r --arg key "$1" 'if .[$key] == null then empty else .[$key] end' "$OPTIONS_FILE")
  else
    value=""
  fi
  if [ -n "$value" ]; then echo "$value"; else echo "$2"; fi
}

lang_code() {
  case "$1" in
    English) echo en ;;
    German) echo de ;;
    Spanish) echo es ;;
    French) echo fr ;;
    Dutch) echo nl ;;
    *) echo "" ;;
  esac
}

# Same download locations as meyayl/docker-languagetool.
ngram_url() {
  base=https://languagetool.org/download/ngram-data
  case "$1" in
    en) echo "$base/ngrams-en-20150817.zip" ;;
    de) echo "$base/ngrams-de-20150819.zip" ;;
    es) echo "$base/ngrams-es-20150915.zip" ;;
    fr) echo "$base/ngrams-fr-20150913.zip" ;;
    nl) echo "$base/ngrams-nl-20181229.zip" ;;
  esac
}

# Convert a Java memory size like 512m or 2g to megabytes.
to_mb() {
  number=${1%?}
  case "$1" in
    *g | *G) echo $((number * 1024)) ;;
    *) echo "$number" ;;
  esac
}

file_size() {
  if [ -f "$1" ]; then stat -c %s "$1"; else echo 0; fi
}

mb() { echo $(($1 / 1048576)); }

# Sleep in the background so a stop request is handled right away.
pause() {
  sleep "$1" &
  wait $! || true
}

# Run a command as the unprivileged languagetool user without any capabilities.
as_languagetool() {
  setpriv --reuid=$LT_UID --regid=$LT_GID --clear-groups \
    --inh-caps=-all --bounding-set=-all --no-new-privs "$@"
}

# Ask the server for the full size of a download.
remote_size() {
  as_languagetool curl -fsSIL --max-time 60 "$1" |
    awk 'tolower($1) == "content-length:" { size = $2 } END { gsub(/\r/, "", size); print size }'
}

# Download the n-grams for one language into ngrams-<code>.zip. Continues a
# partial download from an earlier start instead of starting over.
download_ngrams() {
  code=$1
  url=$(ngram_url "$code")
  zip="$NGRAM_DIR/ngrams-$code.zip"

  attempt=1
  total=""
  while [ -z "$total" ]; do
    total=$(remote_size "$url" || true)
    if [ -z "$total" ]; then
      if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        log "ERROR: Can't reach the n-gram download server for '$code'."
        return 1
      fi
      log "Can't reach the n-gram download server. Trying again in 30 seconds."
      attempt=$((attempt + 1))
      pause 30
    fi
  done

  have=$(file_size "$zip")
  if [ "$have" -gt "$total" ]; then
    log "Download of '$code' n-grams is damaged. Starting it over."
    rm -f "$zip"
    have=0
  fi
  if [ "$have" -eq "$total" ]; then
    log "Download of '$code' n-grams is already complete ($(mb "$total") MB)."
    return 0
  fi
  if [ "$have" -gt 0 ]; then
    log "Continuing download of '$code' n-grams at $(mb "$have") of $(mb "$total") MB."
  else
    log "Downloading '$code' n-grams ($(mb "$total") MB)."
  fi

  attempt=1
  while :; do
    # Abort a stalled connection after 2 minutes below 10 KB/s; the next
    # attempt continues where this one stopped.
    as_languagetool curl -fsSL -C - --speed-limit 10240 --speed-time 120 \
      -o "$zip" "$url" &
    curl_pid=$!
    while kill -0 "$curl_pid" 2>/dev/null; do
      pause 15
      have=$(file_size "$zip")
      log "  Downloaded $(mb "$have") of $(mb "$total") MB ($((have * 100 / total))%)"
    done
    if wait "$curl_pid"; then
      curl_pid=""
      break
    fi
    curl_pid=""

    if [ "$(file_size "$zip")" -eq "$total" ]; then
      break
    fi
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
      log "ERROR: Download of '$code' n-grams failed $MAX_ATTEMPTS times."
      return 1
    fi
    attempt=$((attempt + 1))
    log "Download of '$code' n-grams was interrupted. Continuing in 30 seconds."
    pause 30
  done

  if [ "$(file_size "$zip")" -ne "$total" ]; then
    log "ERROR: Download of '$code' n-grams has the wrong size."
    return 1
  fi
  log "Download of '$code' n-grams complete."
}

# Stop a running download cleanly when Home Assistant stops the app.
curl_pid=""
on_stop() {
  if [ -n "$curl_pid" ]; then kill "$curl_pid" 2>/dev/null || true; fi
  log "Stopped. Downloads continue where they left off on the next start."
  exit 143
}
trap on_stop TERM INT

log "Reading app options."

# --- fastText -----------------------------------------------------------------
if [ "$(option fasttext true)" = "true" ]; then
  log "fastText language detection is enabled."
  disable_fasttext=false
else
  log "fastText language detection is disabled."
  disable_fasttext=true
fi

# --- Java memory --------------------------------------------------------------
java_xms=$(option java_xms 512m)
java_xmx=$(option java_xmx 1536m)

if [ "$(to_mb "$java_xms")" -gt "$(to_mb "$java_xmx")" ]; then
  log "ERROR: Minimum Java memory ($java_xms) is larger than maximum Java memory ($java_xmx)."
  log "ERROR: Please fix this in the app's Configuration tab."
  exit 1
fi
log "Java memory: minimum $java_xms, maximum $java_xmx."

# --- N-gram languages ---------------------------------------------------------
if [ -f "$OPTIONS_FILE" ]; then
  selected_names=$(jq -r '(.ngrams // []) | .[]' "$OPTIONS_FILE")
else
  selected_names="English"
fi

selected_codes=""
for name in $selected_names; do
  code=$(lang_code "$name")
  if [ -z "$code" ]; then
    log "WARNING: Unknown n-gram language '$name', ignoring it."
    continue
  fi
  case " $selected_codes " in
    *" $code "*) ;;
    *) selected_codes="$selected_codes $code" ;;
  esac
done
selected_codes=$(echo "$selected_codes" | xargs)

mkdir -p "$NGRAM_DIR" "$FASTTEXT_DIR"

# Delete data for languages that are no longer selected.
for code in $ALL_LANGS; do
  case " $selected_codes " in
    *" $code "*) continue ;;
  esac
  if [ -e "$NGRAM_DIR/$code" ] || [ -e "$NGRAM_DIR/ngrams-$code.zip" ]; then
    size=$(du -shc "$NGRAM_DIR/$code" "$NGRAM_DIR/ngrams-$code.zip" 2>/dev/null | tail -1 | awk '{print $1}')
    log "N-grams for '$code' are no longer selected. Deleting them (${size})."
    rm -rf "${NGRAM_DIR:?}/$code" "$NGRAM_DIR/ngrams-$code.zip"
  fi
done

# Give the data folders to the unprivileged languagetool user.
find "$NGRAM_DIR" "$FASTTEXT_DIR" \( ! -user $LT_UID -o ! -group $LT_GID \) \
  -exec chown $LT_UID:$LT_GID {} +

log "Free disk space for app data: $(df -h /data | awk 'NR==2 {print $4}')"

ready_codes=""
if [ -n "$selected_codes" ]; then
  log "Selected n-gram languages: $selected_codes"
  for code in $selected_codes; do
    # The zip is deleted after unpacking. A folder next to a leftover zip means
    # unpacking was interrupted, so remove the incomplete folder to unpack again.
    if [ -d "$NGRAM_DIR/$code" ] && [ -f "$NGRAM_DIR/ngrams-$code.zip" ]; then
      log "N-grams for '$code' were not fully unpacked last time. Unpacking them again."
      rm -rf "${NGRAM_DIR:?}/$code"
    elif [ -d "$NGRAM_DIR/$code" ] && [ -z "$(ls -A "$NGRAM_DIR/$code")" ]; then
      log "N-gram folder for '$code' is empty. Downloading it again."
      rm -rf "${NGRAM_DIR:?}/$code"
    fi

    if [ -d "$NGRAM_DIR/$code" ]; then
      log "N-grams for '$code' are installed."
      ready_codes="$ready_codes $code"
      continue
    fi

    log "N-grams for '$code' need to be downloaded and unpacked."
    log "This can take a long time. LanguageTool starts when this is done."
    if download_ngrams "$code"; then
      ready_codes="$ready_codes $code"
    else
      log "WARNING: Starting LanguageTool without '$code' n-grams for now."
      log "WARNING: Restart the app to continue the download."
    fi
  done
else
  log "No n-gram languages selected."
fi

ready_codes=$(echo "$ready_codes" | xargs)
if [ -n "$ready_codes" ]; then
  download_langs=$(echo "$ready_codes" | tr ' ' ',')
else
  download_langs="none"
fi

# --- Hand over to the original entrypoint -------------------------------------
# The entrypoint only unpacks complete downloads and skips installed languages.
export download_ngrams_for_langs="$download_langs"
export DISABLE_FASTTEXT="$disable_fasttext"
export JAVA_XMS="$java_xms"
export JAVA_XMX="$java_xmx"

# Drop root for good: switch to the languagetool user, remove all
# capabilities and block regaining privileges (like Docker's
# --user, --cap-drop ALL and no-new-privileges). Nothing after this runs as root.
log "Dropping root privileges. LanguageTool runs as user 'languagetool' ($LT_UID)."
log "Starting LanguageTool."
trap - TERM INT
exec setpriv --reuid=$LT_UID --regid=$LT_GID --clear-groups \
  --inh-caps=-all --bounding-set=-all --no-new-privs \
  /sbin/tini -g -e 143 -- /entrypoint "$@"
