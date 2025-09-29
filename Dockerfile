FROM bbyars/mountebank@sha256:054aefd743cb43677236ad83f42d54a7e7a4e7bdb2714ecde335ff4b69dff000
WORKDIR /app
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENV MB_HOST=127.0.0.1 \
    MB_PORT=2525 \
    API_PORT=8080 \
    CONFIG_PATH=/config/imposters.yml
EXPOSE 2525
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -qO- http://localhost:2525/ | grep -qi mountebank || exit 1
LABEL org.opencontainers.image.source="https://example.com/your-repo" \
    org.opencontainers.image.description="Reusable mountebank mock service (direct mode only)" \
    org.opencontainers.image.licenses="MIT"
ENTRYPOINT ["/entrypoint.sh"]
