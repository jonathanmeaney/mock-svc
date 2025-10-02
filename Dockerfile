########## Stage 1: build mountebank with controlled dependency graph ##########
# Use latest Node LTS by default; allow override at build time for reproducibility
ARG NODE_IMAGE=node:lts-alpine
FROM ${NODE_IMAGE} AS build
WORKDIR /opt/app

# Accept build arg for mountebank version (default: latest published)
ARG MB_VERSION=latest
ENV MB_VERSION=${MB_VERSION}

# Copy dependency manifest (committed in repo) then install production deps only
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev \
    && npm dedupe \
    && npm cache clean --force

########## Stage 2: runtime ##########
# Re-declare ARG to reuse the same base reference in this stage
ARG NODE_IMAGE=node:lts-alpine
FROM ${NODE_IMAGE} AS runtime
WORKDIR /app

# Create non-root user for security
RUN adduser -D -u 10001 mb

# Copy installed modules only (no source app code needed beyond entrypoint)
COPY --from=build /opt/app/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/mountebank/bin/mb /usr/local/bin/mb

# Entrypoint script (already handles CONFIG_PATH default & JS/YAML conversion)
COPY --chmod=755 entrypoint.sh /entrypoint.sh

ENV MB_HOST=127.0.0.1 \
    MB_PORT=2525

EXPOSE 2525
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -qO- http://localhost:2525/ | grep -qi mountebank || exit 1

LABEL org.opencontainers.image.source="https://github.com/jonathanmeaney/mock-svc" \
      org.opencontainers.image.description="Custom built mountebank mock service (direct mode only)" \
      org.opencontainers.image.licenses="MIT"

RUN chown -R mb:mb /app

USER mb
ENTRYPOINT ["/entrypoint.sh"]
