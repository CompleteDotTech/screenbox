#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
umask 077

if [ ! -f .env ]; then
  API=$(openssl rand -hex 32)
  ADMIN=$(openssl rand -hex 32)
  cp .env.example .env
  sed -i "s/^SCREENBOX_API_TOKEN=.*$/SCREENBOX_API_TOKEN=${API}/" .env
  printf 'SCREENBOX_ADMIN_KEY=%s\n' "$ADMIN" >> .env
  printf 'SCREENBOX_REQUIRE_AUTH=true\n' >> .env
  chmod 600 .env
  echo "[deploy] generated .env with unique tokens"
fi

./setup.sh

echo "=== deploy complete: compose ps ==="
docker compose ps
