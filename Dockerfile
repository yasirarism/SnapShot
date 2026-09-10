# syntax=docker/dockerfile:1
# SnapShot — Web Capture API + Screenshot Tool UI (pnpm monorepo)
# Multi-stage: builder (install + build) → runtime (slim)
#
# NOTE: repo's pnpm-workspace.yaml overrides strip every non-x64 native binary
# (esbuild, rollup, lightningcss, @tailwindcss/oxide). On linux/arm64 that
# leaves the build with NO native binaries → we strip the arm64 exclusions
# before install and re-resolve the lockfile.

# ---------- Stage 1: builder ----------
FROM node:22-bookworm-slim AS builder

ENV PNPM_VERSION=10 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    NODE_ENV=production \
    PORT=8080 \
    BASE_PATH=/

WORKDIR /app

RUN npm install -g pnpm@${PNPM_VERSION} --no-audit --no-fund

# Repo source (node_modules / dist / screenshots-excluded via .dockerignore)
COPY . .

# FIX aarch64: drop arm64 exclusions from pnpm-workspace.yaml
RUN grep -v 'linux-arm64' pnpm-workspace.yaml > .pw.tmp && mv .pw.tmp pnpm-workspace.yaml

# Install (regenerates lockfile with arm64 native deps)
RUN pnpm install --no-frozen-lockfile --reporter=append-only

# Download Playwright Chromium into the shared browsers path
RUN pnpm --filter @workspace/api-server exec playwright install chromium

# Build API server (esbuild bundle → dist/index.mjs)
RUN pnpm --filter @workspace/api-server run build

# Build frontend (vite build → dist/public)
RUN pnpm --filter @workspace/screenshot-tool run build

# ---------- Stage 2: runtime ----------
FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    BASE_PATH=/

# Chromium OS libs + ffmpeg (video recording) + curl (healthcheck)
# Package names are Debian bookworm (no -t64 suffix — that's trixie)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
        curl \
        ca-certificates \
        fonts-liberation \
        libnss3 libnspr4 \
        libatk1.0-0 libatk-bridge2.0-0 libatspi2.0-0 \
        libcups2 libdrm2 libxkbcommon0 \
        libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
        libasound2 libpango-1.0-0 libcairo2 libxshmfence1 \
        libglib2.0-0 libdbus-1-3 libxtst6 libx11-6 libxcb1 libxext6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Browsers + node_modules (pnpm store incl. .pnpm) + built artifacts
COPY --from=builder /ms-playwright /ms-playwright
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/artifacts/api-server/package.json ./artifacts/api-server/package.json
COPY --from=builder /app/artifacts/api-server/node_modules ./artifacts/api-server/node_modules
COPY --from=builder /app/artifacts/api-server/dist ./artifacts/api-server/dist
COPY --from=builder /app/artifacts/screenshot-tool/package.json ./artifacts/screenshot-tool/package.json
COPY --from=builder /app/artifacts/screenshot-tool/node_modules ./artifacts/screenshot-tool/node_modules
COPY --from=builder /app/artifacts/screenshot-tool/dist ./artifacts/screenshot-tool/dist
COPY --from=builder /app/artifacts/screenshot-tool/vite.config.ts ./artifacts/screenshot-tool/vite.config.ts

# Data dirs (screenshots + recordings) — mount volumes here
RUN mkdir -p /app/artifacts/api-server/screenshots /app/artifacts/api-server/videos

COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/snapshot-entrypoint

EXPOSE 8080 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/api/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/snapshot-entrypoint"]