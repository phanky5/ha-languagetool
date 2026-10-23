# Changelog

## 1.0.4

- New option **Speed up checks** (on by default): LanguageTool keeps prepared
  rule sets in memory and remembers results of recently checked sentences,
  so repeated checks are much faster.
- The log no longer shows two lines for every health check (every 30
  seconds). Warnings and errors are still logged.
- The log now shows which n-gram languages are in use when LanguageTool
  starts.

## 1.0.3

- N-gram downloads now continue where they stopped after a restart, update or
  reboot, instead of starting over. Partial downloads from older versions are
  continued too.
- Interrupted downloads are retried automatically.
- The app stops immediately when you stop it during a download.

## 1.0.2

- Security: the app now drops root privileges right after preparing its data
  folders. Everything else, including downloads and LanguageTool itself, runs
  as the unprivileged `languagetool` user with no capabilities and
  no-new-privileges, as recommended by meyayl/docker-languagetool.

## 1.0.1

- Fix: with Watchdog enabled, Home Assistant restarted the app every few
  minutes while n-grams were downloading, so large downloads never finished.
  The health check now waits until downloads are done.

## 1.0.0

- First release.
- Based on meyay/languagetool 6.8-13 (LanguageTool 6.8).
- Choose n-gram languages in the app settings; deselected languages are
  deleted from disk.
- fastText language detection.
- Adjustable Java memory (defaults: minimum 512m, maximum 1536m).
