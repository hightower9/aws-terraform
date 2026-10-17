#!/bin/bash
set -euo pipefail

# Start Floci (local AWS emulator) and its web console for local testing
# of any environment.
# Requires: docker (with compose)
#
# Usage:
#   ./scripts/start-floci.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENDPOINT="http://localhost:4566"

echo "=== Starting Floci ==="
docker compose -f "$ROOT/docker-compose.floci.yml" up -d

echo "Waiting for Floci to be ready..."
for i in $(seq 1 30); do
  if AWS_ENDPOINT_URL="$ENDPOINT" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
     AWS_DEFAULT_REGION=us-east-1 aws sts get-caller-identity >/dev/null 2>&1; then
    echo "Floci ready at $ENDPOINT"
    echo "Web console:   http://localhost:4500   (make floci-ui)"
    echo ""
    echo "Try:  make test-env ENV=local     # full run + app test"
    echo "      make test-env ENV=prod      # prod's real settings, on the emulator"
    echo "      make test-all               # all four environments"
    exit 0
  fi
  sleep 2
done

echo "ERROR: Floci did not become ready within 60s. Logs:" >&2
docker logs --tail 50 floci >&2 || true
exit 1
