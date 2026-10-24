# LanguageTool for Home Assistant

Run your own [LanguageTool](https://languagetool.org) grammar, style and spell
checker on your Home Assistant server. Your texts are checked on your own
hardware and never leave your network.

[![Open your Home Assistant instance and show the dashboard of this app.](https://my.home-assistant.io/badges/supervisor_addon.svg)](https://my.home-assistant.io/redirect/supervisor_addon/?addon=7f3f34b2_languagetool&repository_url=https%3A%2F%2Fgithub.com%2Fphanky5%2Fha-languagetool)

## Features

- Full LanguageTool server with 30+ languages
- **Optional n-gram data** for better detection of commonly confused words.
  Pick the languages you want (English ~9 GB, German, Spanish, French ~1.7 GB
  each, Dutch ~1.2 GB). None are selected by default. Deselected languages are
  removed from disk automatically.
- **fastText** language detection
- Adjustable Java memory
- **Speed up checks**: caches prepared rules and recent results for faster
  checks
- **Secret URL** for safe access from outside your home, for example through
  Cloudflared: LanguageTool only answers at an address with a secret key
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
3. Optional: pick n-gram languages in the **Configuration** tab, if you have
   the disk space. Plan for about three times the download size.
4. Start the app and follow the progress in the **Log** tab.

Full documentation is in the app's **Documentation** tab, or in
[languagetool/DOCS.md](languagetool/DOCS.md).

## Connecting your apps

Once the app is running, your LanguageTool server is at:

```text
http://<your-home-assistant-ip>:8081/v2
```

For example `http://192.168.1.50:8081/v2`, or
`http://homeassistant.local:8081/v2` if your network supports `.local` names.
If you changed the port (see below), use your port instead of `8081`.

| Tool | Where to set it |
| ---- | --------------- |
| **Browser extension** (Chrome, Firefox, Edge, Safari) | Extension icon → ⚙️ **Settings** → **Advanced settings** → **LanguageTool server** → **Other server** → enter the address above |
| **LanguageTool Desktop** (Mac, Windows) | **Settings** → **Advanced** → **LanguageTool server** → **Other server** → enter the address above |
| **LibreOffice** | **Tools → Options → Language Settings → LanguageTool Server** → enable it and enter the address above |
| **Obsidian** (LanguageTool plugin) | Server URL: `http://<your-home-assistant-ip>:8081` (without `/v2`) |

To check that the server works, open
`http://<your-home-assistant-ip>:8081/v2/languages` in your browser. You
should see a list of languages.

With **Secret URL** on, add your key after the port in all of these
addresses, for example `http://<your-home-assistant-ip>:8081/<secret-key>/v2`
(Obsidian: without `/v2`).

> **Note:** the server has no login. Don't forward the port to the internet
> as it is. To use LanguageTool from outside your home, turn on
> [Secret URL](#access-from-outside-your-home).

## Access from outside your home

Turn on **Secret URL** if you make LanguageTool reachable from the internet,
for example with the
[Cloudflared](https://github.com/brenner-tobias/addon-cloudflared) or SSH
tunnel app. LanguageTool then only answers at an address that contains a
secret key:

```text
https://YOUR-DOMAIN/SECRET-KEY/v2
```

Requests without the key get no answer at all, not even an error page. This
also applies on your home network.

1. In the app's **Configuration** tab, turn on **Secret URL** and leave
   **Secret key** empty.
2. Click **Save** and restart the app.
3. The app creates a random 40-character key, saves it in the **Secret key**
   field and shows your secret address in the **Log** tab. Reload the
   Configuration tab to see the key.
4. Point your tunnel at `http://<your-home-assistant-ip>:8081`, without the
   key or any path. For Cloudflared, add this to `additional_hosts`:

   ```yaml
   additional_hosts:
     - hostname: languagetool.example.com
       service: http://192.168.1.50:8081
   ```

5. In your apps, use `https://languagetool.example.com/SECRET-KEY/v2`.

You can also type your own key: 32 to 128 characters, using letters, digits,
`-` and `_`. Upper and lower case count, so `AbC` and `abc` are different
keys. To get a new random key, clear the field and restart the app.

Use HTTPS (Cloudflared does this for you), because over plain `http://` the
key can be read on the way. Treat the address like a password: anyone who
has it can use your server.

## If checks are slow

1. Open the app's **Configuration** tab.
2. Make sure **Speed up checks** is turned on. It is on by default since
   version 1.0.4.
3. Give Java more memory, up to `4g`. Set **Maximum Java memory (JAVA_XMX)**
   to `3g` or `4g`, and set **Minimum Java memory (JAVA_XMS)** to the same
   value.
4. Click **Save** and restart the app.

Only raise the memory if your machine has the RAM to spare. With two n-gram
languages, 8 GB of RAM or more is a good fit for `3g`–`4g`. Going higher than
`4g` doesn't make checks faster. The first check after a restart is always
slower, because LanguageTool has to load its rules first.

## Changing the port

The app uses port **8081** by default. To use a different port, open the app's
**Configuration** tab, scroll to the **Network** section, enter your port next
to **LanguageTool API port**, click **Save** and restart the app.

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
