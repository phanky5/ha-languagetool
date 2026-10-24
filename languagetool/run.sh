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

# Secret URL: nginx listens on the app port and LanguageTool moves here.
APP_PORT=8081
INTERNAL_PORT=8082
SECRET_KEY_FILE=/data/secret_key
SECRET_KEY_LENGTH=40
# Written once the check for old installs with default n-grams has run.
NGRAM_DEFAULT_CHECKED=/data/.ngram_default_checked

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

lang_name() {
  case "$1" in
    en) echo English ;;
    de) echo German ;;
    es) echo Spanish ;;
    fr) echo French ;;
    nl) echo Dutch ;;
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

# Save changed app options through the Supervisor, so they show up in the
# Configuration tab. $1 is a jq filter applied to the options. Earlier saved
# changes are applied too, because options.json isn't updated until restart.
saved_changes="."
save_options() {
  if [ -z "${SUPERVISOR_TOKEN:-}" ] || [ ! -f "$OPTIONS_FILE" ]; then
    return 1
  fi
  changes="$saved_changes | $1"
  if jq -c "{options: ($changes)}" "$OPTIONS_FILE" |
    as_languagetool curl -fsS --max-time 30 -X POST \
      -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @- http://supervisor/addons/self/options >/dev/null 2>&1; then
    saved_changes=$changes
    return 0
  fi
  return 1
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

# --- Speed up checks ----------------------------------------------------------
# The original entrypoint writes every langtool_* variable into LanguageTool's
# config.properties. Not using pipelinePrewarming: it prepares all 30+
# languages at startup, which takes a lot of memory and time.
if [ "$(option speed_up_checks true)" = "true" ]; then
  log "Speed up checks is enabled: rule sets and results are cached."
  # Reuse prepared rule sets instead of building them for every check.
  export langtool_pipelineCaching=true
  export langtool_maxPipelinePoolSize=20
  export langtool_pipelineExpireTimeInSeconds=3600
  # Remember results of recently checked sentences.
  export langtool_cacheSize=5000
else
  log "Speed up checks is disabled."
fi

# --- Secret URL ---------------------------------------------------------------
# With a secret URL, nginx answers on the app port and only passes requests
# under /<key>/ on to LanguageTool, which then listens on localhost only.
secret_url=false
if [ "$(option secret_url false)" = "true" ]; then
  secret_url=true
  secret_key=$(option secret_key "")
  if [ -z "$secret_key" ]; then
    if [ -s "$SECRET_KEY_FILE" ]; then
      # Made on an earlier start, but couldn't be saved to the options then.
      secret_key=$(cat "$SECRET_KEY_FILE")
    else
      secret_key=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$SECRET_KEY_LENGTH")
      log "Created a new secret key."
    fi
    if save_options ".secret_key = \"$secret_key\""; then
      rm -f "$SECRET_KEY_FILE"
      log "The key is saved in the Configuration tab (reload the page to see it)."
    else
      (umask 077 && echo "$secret_key" >"$SECRET_KEY_FILE")
      log "WARNING: Couldn't save the key to the Configuration tab."
      log "WARNING: The app keeps it. Copy it from the line below."
    fi
    log "Your secret URL: http://<your-home-assistant-ip>:$APP_PORT/$secret_key/v2"
  else
    rm -f "$SECRET_KEY_FILE"
    if ! echo "$secret_key" | grep -Eq '^[A-Za-z0-9_-]{32,128}$'; then
      log "ERROR: The secret key must be 32 to 128 characters long and use only"
      log "ERROR: letters, digits, '-' and '_'. Clear the field to get a new key."
      exit 1
    fi
    log "Your secret URL: http://<your-home-assistant-ip>:$APP_PORT/$(echo "$secret_key" | cut -c1-4).../v2"
    log "The full key is in the Configuration tab."
  fi
  log "Secret URL is enabled. Requests without the key get no answer."
else
  log "Secret URL is disabled."
  rm -f "$SECRET_KEY_FILE"
fi

# --- N-gram languages ---------------------------------------------------------
if [ -f "$OPTIONS_FILE" ]; then
  selected_names=$(jq -r '(.ngrams // []) | .[]' "$OPTIONS_FILE")
else
  selected_names=""
fi

# Up to version 1.0.4, English was selected by default. Home Assistant only
# keeps options that were saved, so an install that never saved its options
# now gets the new empty default. Keep English for those installs instead of
# deleting ~9 GB of data, and save the choice so it shows in the settings.
if [ ! -f "$NGRAM_DEFAULT_CHECKED" ]; then
  if [ -z "$selected_names" ] &&
    { [ -d "$NGRAM_DIR/en" ] || [ -f "$NGRAM_DIR/ngrams-en.zip" ]; }; then
    log "English n-grams were selected by default before version 1.1.0. Keeping them."
    log "To remove them, deselect English in the Configuration tab."
    selected_names="English"
    if save_options '.ngrams = ["English"]'; then
      touch "$NGRAM_DEFAULT_CHECKED"
    else
      # Not marking the check as done, so the data is kept on the next start too.
      log "WARNING: Couldn't save English to the app options."
      log "WARNING: Select English in the Configuration tab to keep these n-grams."
    fi
  else
    touch "$NGRAM_DEFAULT_CHECKED"
  fi
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
  log "No n-gram languages selected. You can pick some in the Configuration tab."
fi

ready_codes=$(echo "$ready_codes" | xargs)
if [ -n "$ready_codes" ]; then
  download_langs=$(echo "$ready_codes" | tr ' ' ',')
  names=""
  for code in $ready_codes; do
    names="${names:+$names, }$(lang_name "$code")"
  done
  log "N-gram languages in use: $names"
else
  download_langs="none"
  log "N-gram languages in use: none"
fi

# --- nginx for the secret URL -------------------------------------------------
listen_port=$APP_PORT
if [ "$secret_url" = "true" ]; then
  listen_port=$INTERNAL_PORT
  conf_dir=/tmp/nginx
  rm -rf "$conf_dir"
  mkdir -p "$conf_dir"
  sed -e "s|@APP_PORT@|$APP_PORT|g" \
    -e "s|@INTERNAL_PORT@|$INTERNAL_PORT|g" \
    -e "s|@SECRET_KEY@|$secret_key|g" \
    -e "s|@CONF_DIR@|$conf_dir|g" \
    /ha-nginx.conf >"$conf_dir/nginx.conf"
  chown -R $LT_UID:$LT_GID "$conf_dir"
  chmod 700 "$conf_dir"
  chmod 600 "$conf_dir/nginx.conf"
  log "Starting nginx for the secret URL."
  as_languagetool nginx -c "$conf_dir/nginx.conf" -e stderr &
  nginx_pid=$!
  pause 2
  if ! kill -0 "$nginx_pid" 2>/dev/null; then
    log "ERROR: nginx didn't start, see the lines above."
    exit 1
  fi
  # Makes LanguageTool listen on localhost only, see java-wrapper.sh.
  export PATH="/usr/local/ha-bin:$PATH"
fi
# The health check reads the LanguageTool port from here.
echo "$listen_port" >/tmp/ha-listen-port

# --- Hand over to the original entrypoint -------------------------------------
# The entrypoint only unpacks complete downloads and skips installed languages.
export download_ngrams_for_langs="$download_langs"
export DISABLE_FASTTEXT="$disable_fasttext"
export JAVA_XMS="$java_xms"
export JAVA_XMX="$java_xmx"
export LISTEN_PORT="$listen_port"

# Drop root for good: switch to the languagetool user, remove all
# capabilities and block regaining privileges (like Docker's
# --user, --cap-drop ALL and no-new-privileges). Nothing after this runs as root.
log "Dropping root privileges. LanguageTool runs as user 'languagetool' ($LT_UID)."
log "Starting LanguageTool."
trap - TERM INT
exec setpriv --reuid=$LT_UID --regid=$LT_GID --clear-groups \
  --inh-caps=-all --bounding-set=-all --no-new-privs \
  /sbin/tini -g -e 143 -- /entrypoint "$@"
