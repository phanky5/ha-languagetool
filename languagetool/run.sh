#!/bin/sh
# Start script for the LanguageTool Home Assistant app.
# Reads the app options, removes n-gram data for deselected languages,
# then hands over to the original meyay/languagetool entrypoint.
set -eu

OPTIONS_FILE=/data/options.json
NGRAM_DIR=/data/ngrams
FASTTEXT_DIR=/data/fasttext
ALL_LANGS="en de es fr nl"

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

# Convert a Java memory size like 512m or 2g to megabytes.
to_mb() {
  number=${1%?}
  case "$1" in
    *g | *G) echo $((number * 1024)) ;;
    *) echo "$number" ;;
  esac
}

log "Reading app options."

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
    if [ ! -d "$NGRAM_DIR/$code" ]; then
      log "N-grams for '$code' will be downloaded and unpacked now."
      log "This can take a long time. LanguageTool starts when this is done. Progress is shown below."
    fi
  done
  download_langs=$(echo "$selected_codes" | tr ' ' ',')
else
  log "No n-gram languages selected."
  download_langs="none"
fi

log "Free disk space for app data: $(df -h /data | awk 'NR==2 {print $4}')"

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

# --- Hand over to the original entrypoint -------------------------------------
export download_ngrams_for_langs="$download_langs"
export DISABLE_FASTTEXT="$disable_fasttext"
export JAVA_XMS="$java_xms"
export JAVA_XMX="$java_xmx"

# Give the data folders to the unprivileged languagetool user (uid/gid 783).
find "$NGRAM_DIR" "$FASTTEXT_DIR" \( ! -user 783 -o ! -group 783 \) -exec chown 783:783 {} +

# Drop root for good: switch to the languagetool user, remove all
# capabilities and block regaining privileges (like Docker's
# --user, --cap-drop ALL and no-new-privileges). Nothing after this runs as root.
log "Dropping root privileges. LanguageTool runs as user 'languagetool' (783)."
log "Starting LanguageTool."
exec setpriv --reuid=783 --regid=783 --clear-groups \
  --inh-caps=-all --bounding-set=-all --no-new-privs \
  /sbin/tini -g -e 143 -- /entrypoint "$@"
