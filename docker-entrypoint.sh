#!/bin/sh
set -eu

echo "[snapshot] Starting API server on :8080 ..."
cd /app/artifacts/api-server
PORT=8080 node dist/index.mjs &
API_PID=$!

ready=0
for i in $(seq 1 40); do
  if curl -fsS http://127.0.0.1:8080/api/healthz >/dev/null 2>&1; then
    echo "[snapshot] API ready (after ${i}s)"
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "[snapshot] API failed to start in time (last lines below):" >&2
  kill "$API_PID" 2>/dev/null || true
  exit 1
fi

echo "[snapshot] Starting frontend (vite preview) on :5000 ..."
cd /app/artifacts/screenshot-tool
trap 'echo "[snapshot] Shutting down API"; kill "$API_PID" 2>/dev/null || true' INT TERM EXIT
PORT=5000 BASE_PATH=/ NODE_ENV=production \
  node node_modules/vite/bin/vite.js preview --config vite.config.ts