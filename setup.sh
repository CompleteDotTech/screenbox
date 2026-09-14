#!/bin/bash
# Screenbox setup & update
# Works on Linux, macOS, Windows (Git Bash / WSL)
# First run: generates .env, builds images, shows onboarding
# Update: rebuilds images, restarts services
set -e

cd "$(dirname "$0")"

# Pre-flight: Docker must be running
if ! docker info >/dev/null 2>&1; then
  echo ""
  echo "[ERROR] Docker daemon is not running."
  echo ""
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  On macOS: open Docker.app, wait for it to be ready, then rerun ./setup.sh"
  elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    echo "  On Windows: start Docker Desktop, wait for it to be ready, then rerun ./setup.sh"
  else
    echo "  Start Docker: sudo systemctl start docker"
    echo "  Then rerun: ./setup.sh"
  fi
  echo ""
  exit 1
fi

# Cross-platform sed -i (macOS requires '' argument)
_sed_i() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Detect: first install or update
IS_UPDATE=false
if [ -f .env ] && docker compose ps --quiet 2>/dev/null | grep -q .; then
  IS_UPDATE=true
fi

if [ "$IS_UPDATE" = true ]; then
  echo "Screenbox update"
  echo "================"
else
  echo "Screenbox setup"
  echo "==============="
fi
echo ""

# 1. Generate .env if missing
if [ ! -f .env ]; then
  TOKEN=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
  cp .env.example .env
  _sed_i "s/^SCREENBOX_API_TOKEN=$/SCREENBOX_API_TOKEN=${TOKEN}/" .env
  echo "[OK] Created .env with API token"
else
  echo "[OK] .env already exists"
fi

# Check token is set
TOKEN_VAL=$(grep "^SCREENBOX_API_TOKEN=" .env | cut -d= -f2)
if [ -z "$TOKEN_VAL" ]; then
  TOKEN=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
  _sed_i "s/^SCREENBOX_API_TOKEN=$/SCREENBOX_API_TOKEN=${TOKEN}/" .env
  TOKEN_VAL="$TOKEN"
  echo "[OK] Generated API token"
fi

# 2. Create data directories and set host paths
mkdir -p data/desktops data/logs data/knowledge data/recordings
if ! grep -q "^SCREENBOX_RECORDINGS_HOST_DIR=" .env 2>/dev/null; then
  echo "SCREENBOX_RECORDINGS_HOST_DIR=$(pwd)/data/recordings" >> .env
fi
echo "[OK] Data directories"

# 3. (hardened) Do NOT write .mcp.json -- it embeds the admin API token on disk.
# Provide credentials to the agent runner through its own secret storage instead.
echo "[OK] Skipping .mcp.json (hardened build)"

# 4. Build all images
echo ""
echo "Building desktop image..."
docker build -f docker/Dockerfile -t screenbox:latest docker/
echo "[OK] Desktop image"

echo ""
echo "Building MCP server and dashboard..."
DOCKER_BUILDKIT=0 docker compose build screenbox-socket-proxy screenbox-mcp screenbox-dashboard
echo "[OK] All images built"

# 5. Stop old containers and start new ones
echo ""
if [ "$IS_UPDATE" = true ]; then
  echo "Restarting services..."
  docker compose down 2>/dev/null || true
fi
docker compose up -d
echo "[OK] Services running"

# 5b. (hardened) Do NOT create a shared demo desktop on first install.
# Desktops must be created by/for a specific agent identity.
echo "[OK] Skipping demo desktop (hardened build)"

# 6. Integration test
echo ""
echo "Running integration test..."
if ./test-integration.sh; then
  echo "[OK] Integration test passed"
else
  echo ""
  echo "[WARN] Integration test failed -- services may still be starting."
  echo "       Wait 30 seconds and try: curl http://localhost:8080/mcp"
fi

# 7. Show result
echo ""
echo "==============="
if [ "$IS_UPDATE" = true ]; then
  echo "Update complete!"
  echo ""
  echo "Services restarted on new images."
  echo "Existing desktops use the old image -- recreate them:"
  echo "  - Dashboard: destroy + create"
  echo "  - Or: curl -s -X POST -H 'Content-Type: application/json' \\"
  echo "    -d '{\"id\":\"desktop-1\",\"auto_snapshot\":false}' http://localhost:8080/api/desktop/destroy"
  echo "  - Then: curl -s -X POST -H 'Content-Type: application/json' \\"
  echo "    -d '{\"id\":\"desktop-1\"}' http://localhost:8080/api/desktop/create"
else
  echo "Screenbox ready!"
  echo ""
  echo "Dashboard (token auth enabled -- enter the API token when prompted):"
  echo "  http://localhost:16000"
  echo ""
  echo "MCP endpoint: http://localhost:8080/mcp"
  echo "  Provide the API token via Authorization: Bearer <token>."
  echo "  The token is in .env (SCREENBOX_API_TOKEN). Do not commit or share it."
fi
