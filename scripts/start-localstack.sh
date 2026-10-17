#!/bin/bash
set -euo pipefail

# Start LocalStack for local development.
# Requires: docker, localstack CLI
#
# Usage:
#   ./scripts/start-localstack.sh

echo "=== Starting LocalStack ==="

if ! command -v localstack &>/dev/null; then
  echo "ERROR: localstack CLI not found. Install with: pip install localstack"
  exit 1
fi

localstack start -d

echo "Waiting for LocalStack to be ready..."
localstack wait -t 30

echo "LocalStack services:"
localstack status

echo ""
echo "LocalStack endpoint: http://localhost:4566"
echo "Run: make init-local && make plan-local"
