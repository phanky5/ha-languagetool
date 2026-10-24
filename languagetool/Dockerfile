ARG BUILD_FROM=meyay/languagetool:6.8-13
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# jq reads the app options that Home Assistant writes to /data/options.json.
# setpriv drops root privileges, curl downloads n-grams with resume support.
# nginx serves the secret URL when that option is on.
# hadolint ignore=DL3018
RUN apk add --no-cache curl jq nginx setpriv

COPY run.sh /ha-run.sh
COPY healthcheck.sh /ha-healthcheck.sh
COPY logback.xml /ha-logback.xml
COPY nginx.conf /ha-nginx.conf
COPY java-wrapper.sh /usr/local/ha-bin/java
RUN chmod a+x /ha-run.sh /ha-healthcheck.sh /usr/local/ha-bin/java

# Replace the image's health check: it fails while n-grams are downloading,
# which makes Home Assistant's watchdog restart the app and lose the download.
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
  CMD ["/ha-healthcheck.sh"]

# Keep all downloaded data in the app's persistent /data folder
ENV langtool_languageModel=/data/ngrams \
    langtool_fasttextModel=/data/fasttext/lid.176.bin

# Same logging as the image, without a log line for every health check
ENV LOGBACK_CONFIG=/ha-logback.xml

# run.sh prepares /data as root, then drops privileges and starts tini
ENTRYPOINT ["/ha-run.sh"]

LABEL org.opencontainers.image.title="LanguageTool for Home Assistant" \
      org.opencontainers.image.source="https://github.com/phanky5/ha-languagetool" \
      org.opencontainers.image.licenses="MIT"
