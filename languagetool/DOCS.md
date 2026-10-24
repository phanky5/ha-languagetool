# LanguageTool

This app runs a private [LanguageTool](https://languagetool.org) server on your
Home Assistant machine. Point your browser extension, LibreOffice or other
tools at it to check spelling, grammar and style without sending your texts to
the internet.

## First start

1. Optional: open the **Configuration** tab and choose n-gram languages, if
   you have the disk space (see below). None are selected by default.
2. Start the app and open the **Log** tab.

On the first start the app downloads the fastText model (~130 MB) and any
n-gram languages you picked. **English n-grams are about 9 GB**, so this can
take a long time depending on your internet connection. LanguageTool starts
once all downloads are finished. You'll see this line in the log when it's
ready:

```text
Server started
```

If the app is restarted or stopped during a download, the download continues
where it left off on the next start. Short network problems are retried
automatically.

Later starts are fast, because the data is kept.

## Configuration

### N-gram languages

N-grams are large word statistics that help LanguageTool spot commonly confused
words, for example *their / there* or *then / than*. They are optional and
none are selected by default. Choose any of:

| Language | Download size |
| -------- | ------------- |
| English  | ~9.0 GB       |
| German   | ~1.7 GB       |
| Spanish  | ~1.7 GB       |
| French   | ~1.8 GB       |
| Dutch    | ~1.2 GB       |

Unpacked, the data takes roughly **twice** the download size. While a language
is being installed, the download and the unpacked data exist at the same time,
so plan for about **three times** the download size of free disk space
(around 30 GB for English).

- Selecting a language downloads it on the next start.
- **Deselecting a language deletes its data** on the next start, freeing the
  disk space.
- Selecting no language at all is fine: LanguageTool still checks spelling and
  grammar, just without the n-gram rules.

Before version 1.1.0, English was selected by default. If you updated from an
older version without ever saving your settings, the app keeps your English
n-grams and adds English to your settings, so nothing is deleted.

### fastText language detection

Uses the fastText model (~130 MB) to detect the language of a text faster and
more reliably. Enabled by default.

### Java memory

- **Minimum Java memory (JAVA_XMS)** — default `512m`
- **Maximum Java memory (JAVA_XMX)** — default `1536m`

Use a number followed by `m` (megabytes) or `g` (gigabytes), for example
`1g` or `2048m`. The minimum must not be larger than the maximum. If
LanguageTool is slow or crashes with "OutOfMemoryError", raise the maximum,
as long as your machine has the RAM to spare.

### Speed up checks

Enabled by default. LanguageTool keeps the prepared rules for each language
in memory instead of building them again for every check, and remembers the
results of the last 5,000 checked sentences. This makes checks much faster,
especially with the browser extension, which sends your text again and again
while you type. It uses some extra memory. The first check per language after
a start is still slow.

Turn it off only if the app runs short of memory.

### Secret URL

Off by default. Turn it on when LanguageTool is reachable from outside your
home, for example through the Cloudflared or SSH tunnel app. LanguageTool
then only answers at an address that contains a secret key:

```text
http://<your-home-assistant-ip>:8081/<secret key>/v2
```

Any request without the key, including the normal `/v2` address, gets no
answer at all. This also applies on your home network.

To turn it on:

1. Turn on **Secret URL** and leave **Secret key** empty.
2. Click **Save** and restart the app.
3. The app creates a random 40-character key, saves it in the **Secret key**
   field and shows your secret address in the **Log** tab. Reload the
   Configuration tab to see the key.

To use your own key, type it into **Secret key**, save and restart. It must be
32 to 128 characters long and may contain letters, digits, `-` and `_`. Upper
and lower case count, so `AbC` and `abc` are different keys. To get a new
random key, clear the field and restart. If the key is too short or has other
characters, the app doesn't start and the log says why.

See [Access from outside your home](#access-from-outside-your-home) for a
setup example.

### Port

The app uses port **8081** by default. To use a different port:

1. Scroll down to the **Network** section of this Configuration tab.
2. Enter your port next to **LanguageTool API port**.
3. Click **Save** and restart the app.

Use your port instead of `8081` in all addresses below.

## Connecting your apps

The server address is:

```text
http://<your-home-assistant-ip>:8081/v2
```

For example `http://192.168.1.50:8081/v2`, or
`http://homeassistant.local:8081/v2` if your network supports `.local` names.

- **Browser extension** (Chrome, Firefox, Edge, Safari): click the extension
  icon → ⚙️ **Settings** → **Advanced settings** → **LanguageTool server** →
  **Other server** and enter the address above.
- **LanguageTool Desktop** (Mac, Windows): **Settings** → **Advanced** →
  **LanguageTool server** → **Other server** and enter the address above.
- **LibreOffice**: **Tools → Options → Language Settings → LanguageTool Server**,
  enable it and enter the address above.
- **Obsidian** (LanguageTool plugin): set the server URL to
  `http://<your-home-assistant-ip>:8081` (without `/v2`).

To check that the server works, open this address in a browser:

```text
http://<your-home-assistant-ip>:8081/v2/languages
```

You should see a list of supported languages.

With **Secret URL** on, put the key after the port in all of these addresses,
for example `http://<your-home-assistant-ip>:8081/<secret key>/v2`. For
Obsidian use `http://<your-home-assistant-ip>:8081/<secret key>` (without
`/v2`).

## Access from outside your home

The server has no login, so never forward port 8081 to the internet as it is.
To use LanguageTool on the go, combine a tunnel with **Secret URL**:

1. Turn on **Secret URL** (see above) and copy the key.
2. Set up the tunnel. With the
   [Cloudflared app](https://github.com/brenner-tobias/addon-cloudflared), add
   an entry to `additional_hosts` that points your hostname to
   `http://<your-home-assistant-ip>:8081`, without the key or any path:

   ```yaml
   additional_hosts:
     - hostname: languagetool.example.com
       service: http://192.168.1.50:8081
   ```

3. In your apps, use `https://languagetool.example.com/<secret key>/v2`.

Some tips:

- Use HTTPS, which Cloudflared gives you. Over plain `http://` the key can be
  read on the way.
- Treat the address like a password. Anyone who has it can use your server.
- If the key gets out, clear the **Secret key** field and restart the app to
  get a new one. Then update your apps.

## Backups

The n-gram data and the fastText model are **not** included in Home Assistant
backups, to keep them small. After restoring a backup, the app downloads the
data again on its next start.

## Security

The app only uses root briefly at startup to prepare its data folders. It then
switches to the unprivileged `languagetool` user, removes all special
permissions and blocks regaining them. Downloads and LanguageTool itself never
run as root.

The server has no login. Anyone who can reach port 8081 can use it. Don't
expose this port to the internet without **Secret URL**.

With **Secret URL** on, a small nginx web server answers on port 8081 and only
passes requests with the key on to LanguageTool. LanguageTool itself then only
listens inside the app, so other apps can't reach it around nginx. nginx runs
as the `languagetool` user too, and it doesn't log requests, so the key
doesn't end up in the log. The app needs access to the Supervisor API only to
save a newly created key to its own settings.

## Support

Problems or ideas? Open an issue at
<https://github.com/phanky5/ha-languagetool/issues>.

This app builds on
[meyayl/docker-languagetool](https://github.com/meyayl/docker-languagetool).
It is a community project and is not affiliated with LanguageTool or
Home Assistant.
