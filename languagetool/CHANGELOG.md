# Changelog

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
