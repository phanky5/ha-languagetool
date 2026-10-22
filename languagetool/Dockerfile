ARG BUILD_FROM=meyay/languagetool:6.8-13
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# jq reads the app options that Home Assistant writes to /data/options.json
# hadolint ignore=DL3018
RUN apk add --no-cache jq

COPY run.sh /ha-run.sh
RUN chmod a+x /ha-run.sh

# Keep all downloaded data in the app's persistent /data folder
ENV langtool_languageModel=/data/ngrams \
    langtool_fasttextModel=/data/fasttext/lid.176.bin

ENTRYPOINT ["/sbin/tini", "-g", "-e", "143", "--", "/ha-run.sh"]

LABEL org.opencontainers.image.title="LanguageTool for Home Assistant" \
      org.opencontainers.image.source="https://github.com/phanky5/ha-languagetool" \
      org.opencontainers.image.licenses="MIT"
