# LanguageTool

This app runs a private [LanguageTool](https://languagetool.org) server on your
Home Assistant machine. Point your browser extension, LibreOffice or other
tools at it to check spelling, grammar and style without sending your texts to
the internet.

## First start

1. Open the **Configuration** tab and choose your n-gram languages
   (English is selected by default).
2. Start the app and open the **Log** tab.

On the first start the app downloads the n-gram data and the fastText model.
**English n-grams are about 9 GB**, so this can take a long time depending on
your internet connection. LanguageTool starts once all downloads are finished.
You'll see this line in the log when it's ready:

```text
Server started
```

Later starts are fast, because the data is kept.

## Configuration

### N-gram languages

N-grams are large word statistics that help LanguageTool spot commonly confused
words, for example *their / there* or *then / than*. Choose any of:

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

### Network port

The LanguageTool API listens on port **8081**. You can change the port in the
**Network** section of the Configuration tab.

## Using the server

The server address is:

```text
http://<your-home-assistant-ip>:8081/v2
```

Some examples:

- **Browser extension** (Chrome, Firefox, Edge, Safari): open the extension
  settings → **Advanced settings** → **LanguageTool server** → **Other server**
  and enter the address above.
- **LibreOffice**: **Tools → Options → Language Settings → LanguageTool Server**,
  enable it and enter the address above.
- **Obsidian** (LanguageTool plugin): set the server URL to
  `http://<your-home-assistant-ip>:8081`.

To check that the server works, open this address in a browser:

```text
http://<your-home-assistant-ip>:8081/v2/languages
```

You should see a list of supported languages.

## Backups

The n-gram data and the fastText model are **not** included in Home Assistant
backups, to keep them small. After restoring a backup, the app downloads the
data again on its next start.

## Security

The server has no login. Anyone who can reach port 8081 can use it. Don't
expose this port to the internet.

## Support

Problems or ideas? Open an issue at
<https://github.com/phanky5/ha-languagetool/issues>.

This app builds on
[meyayl/docker-languagetool](https://github.com/meyayl/docker-languagetool).
It is a community project and is not affiliated with LanguageTool or
Home Assistant.
