# LanguageTool for Home Assistant

Run your own [LanguageTool](https://languagetool.org) grammar, style and spell
checker on your Home Assistant server. Your texts are checked on your own
hardware and never leave your network.

[![Open your Home Assistant instance and show the dashboard of this app.](https://my.home-assistant.io/badges/supervisor_addon.svg)](https://my.home-assistant.io/redirect/supervisor_addon/?addon=7f3f34b2_languagetool&repository_url=https%3A%2F%2Fgithub.com%2Fphanky5%2Fha-languagetool)

## Features

- Full LanguageTool server with 30+ languages
- **N-gram data** for better detection of commonly confused words — pick the
  languages you want (English, German, Spanish, French, Dutch). Deselected
  languages are removed from disk automatically.
- **fastText** language detection
- Adjustable Java memory
- Large downloads are excluded from Home Assistant backups
- Works with the official LanguageTool browser extensions, LibreOffice, Obsidian
  and anything else that can use a custom LanguageTool server

Supported hardware: **amd64** (Intel/AMD) and **aarch64** (64-bit ARM, e.g.
Raspberry Pi 4/5 with a 64-bit OS).

## Installation

1. Click the button above, or in Home Assistant go to
   **Settings → Apps → App store → ⋮ → Repositories** and add
   `https://github.com/phanky5/ha-languagetool`.
2. Install the **LanguageTool** app.
3. Pick your n-gram languages in the **Configuration** tab.
4. Start the app and follow the progress in the **Log** tab.

Full documentation is in the app's **Documentation** tab, or in
[languagetool/DOCS.md](languagetool/DOCS.md).

## Credits

This app builds on the excellent
[meyayl/docker-languagetool](https://github.com/meyayl/docker-languagetool)
image, which does the heavy lifting. LanguageTool is developed by
[LanguageTool](https://github.com/languagetool-org/languagetool) and licensed
under LGPL-2.1.

This is a community project and is not affiliated with LanguageTool or
Home Assistant.

## License

The files in this repository are licensed under the [MIT License](LICENSE).
