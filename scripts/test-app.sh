#!/bin/bash
set -euo pipefail

# Run the app container locally exactly as cloud-init runs it on EC2
# (same image, port mapping, env file and health check), using the
# settings from environments/<env>/terraform.tfvars. If Floci is running
# and the env has been applied there, the app config/secrets are loaded
# from its SSM path (like on EC2) and AWS calls go to the emulator.
#
# Usage:
#   ./scripts/test-app.sh <env>                       # local | dev | uat | prod
#   IMAGE=laravel-app:dev ./scripts/test-app.sh dev   # test a locally built image
#   PORT=8081 ./scripts/test-app.sh dev               # different host port
#   KEEP=1 ./scripts/test-app.sh dev                  # leave the container running

ENV_NAME="${1:?usage: test-app.sh <env>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TFVARS="$ROOT/environments/$ENV_NAME/terraform.tfvars"
[ -f "$TFVARS" ] || { echo "ERROR: $TFVARS not found" >&2; exit 1; }

# Read a scalar from tfvars, falling back to the variables.tf default.
tfvar() {
  local v
  v=$(sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"#]*)\"?.*/\1/p" "$TFVARS" | head -1 | sed 's/[[:space:]]*$//')
  echo "${v:-$2}"
}

PROJECT=$(tfvar project laravel)
REGION=$(tfvar aws_region us-east-1)
IMAGE="${IMAGE:-$(tfvar docker_image laravel-app):$(tfvar docker_tag latest)}"
APP_PORT="${PORT:-$(tfvar app_port 8000)}"
CONTAINER_PORT=$(tfvar container_port 8000)
HEALTH_PATH=$(tfvar health_check_url /health)
WAIT_LIMIT=$(tfvar startup_timeout 120)
CONTAINER_NAME="$PROJECT-$ENV_NAME-app-test"
HEALTH_URL="http://localhost:$APP_PORT$HEALTH_PATH"
ENV_FILE="$(mktemp)"

cleanup() {
  rm -f "$ENV_FILE"
  if [ "${KEEP:-0}" != "1" ]; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

EMULATOR_ARGS=()
if curl -fsS --max-time 2 http://localhost:4566/_floci/health >/dev/null 2>&1; then
  echo "=== Floci detected: wiring container to the emulator ==="
  # Same env file cloud-init builds on EC2. MSYS_NO_PATHCONV stops Git Bash
  # on Windows from rewriting the /<project>/<env>/app path.
  MSYS_NO_PATHCONV=1 AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test \
    AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION="$REGION" \
    aws ssm get-parameters-by-path --path "/$PROJECT/$ENV_NAME/app" --recursive \
    --with-decryption --query 'Parameters[].[Name,Value]' --output text 2>/dev/null |
    while IFS=$'\t' read -r NAME VALUE; do
      if [ -n "$NAME" ] && [ "$NAME" != "None" ]; then
        echo "$(basename "$NAME")=$VALUE"
      fi
    done > "$ENV_FILE" || true

  if [ -s "$ENV_FILE" ]; then
    echo "=== Loaded $(wc -l < "$ENV_FILE" | tr -d ' ') settings from SSM: $(cut -d= -f1 "$ENV_FILE" | tr '\n' ' ')==="
  else
    echo "=== No SSM config for $ENV_NAME in Floci yet (run: make test-env ENV=$ENV_NAME) ==="
  fi

  EMULATOR_ARGS=(
    --add-host=host.docker.internal:host-gateway
    -e AWS_ENDPOINT_URL=http://host.docker.internal:4566
    -e AWS_ACCESS_KEY_ID=test
    -e AWS_SECRET_ACCESS_KEY=test
    -e AWS_USE_PATH_STYLE_ENDPOINT=true
  )
fi

echo "=== [$ENV_NAME] image=$IMAGE  host:$APP_PORT -> container:$CONTAINER_PORT  health=$HEALTH_PATH ==="

# Prefer a locally built image (e.g. `docker build -t laravel-app .`).
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "=== Pulling $IMAGE ==="
  docker pull "$IMAGE"
fi

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "$APP_PORT:$CONTAINER_PORT" \
  --env-file "$ENV_FILE" \
  -e AWS_REGION="$REGION" \
  "${EMULATOR_ARGS[@]}" \
  "$IMAGE" >/dev/null

echo "=== Waiting up to $WAIT_LIMIT seconds for $HEALTH_URL ==="
START=$(date +%s)
while [ $(( $(date +%s) - START )) -lt "$WAIT_LIMIT" ]; do
  if ! docker ps -q --filter "name=^$CONTAINER_NAME$" | grep -q .; then
    echo "FAIL: container exited. Logs:" >&2
    docker logs --tail 50 "$CONTAINER_NAME" >&2 || true
    exit 1
  fi
  if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null 2>&1; then
    echo "PASS: [$ENV_NAME] app healthy at $HEALTH_URL after $(( $(date +%s) - START ))s"
    [ "${KEEP:-0}" = "1" ] && echo "Container left running: $CONTAINER_NAME"
    exit 0
  fi
  sleep 2
done

echo "FAIL: app never became healthy within $WAIT_LIMIT seconds. Logs:" >&2
docker logs --tail 50 "$CONTAINER_NAME" >&2 || true
exit 1
