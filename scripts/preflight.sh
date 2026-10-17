#!/bin/bash
set -euo pipefail

# Refuse to plan a real-AWS environment that still has dummy values.
# Run automatically by `make plan` (not for EMULATOR=1 / local).
#
#   prod      -> any "# PLACEHOLDER" left is an ERROR (plan stops)
#   dev / uat -> placeholders are listed as WARNINGS
#
# Usage: ./scripts/preflight.sh <env>

ENV_NAME="${1:?usage: preflight.sh <env>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/environments/$ENV_NAME"
TFVARS="$DIR/terraform.tfvars"

tfvar() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"#]*)\"?.*/\1/p" "$TFVARS" | head -1 | sed 's/[[:space:]]*$//'
}

PROBLEMS=()
while IFS= read -r line; do
  PROBLEMS+=("$line")
done < <(grep -HnE '^[^#]*# PLACEHOLDER' "$TFVARS" "$DIR/backend.tfbackend" 2>/dev/null | sed "s|$ROOT/||" || true)

# Report a semantic problem only when its line isn't already flagged above.
check() {
  local key="$1" bad="$2" msg="$3"
  grep -qE "^[[:space:]]*$key[[:space:]]*=.*# PLACEHOLDER" "$TFVARS" && return 0
  [ "$bad" = "1" ] && PROBLEMS+=("$key: $msg")
  return 0
}

# Belt and braces for prod: catch dummies even if the marker was deleted.
if [ "$ENV_NAME" = "prod" ]; then
  check docker_image        "$([ "$(tfvar docker_image)" = "nginx" ] && echo 1)" "still the nginx stand-in"
  check docker_tag          "$([ "$(tfvar docker_tag)" = "latest" ] && echo 1)" "must be an immutable tag, not latest"
  check acm_certificate_arn "$([ -z "$(tfvar acm_certificate_arn)" ] && echo 1)" "empty: prod must serve HTTPS"
  check alarm_email         "$([ -z "$(tfvar alarm_email)" ] && echo 1)" "empty: nobody would be paged"
  check ami_id              "$([ -z "$(tfvar ami_id)" ] && echo 1)" "empty: pin the AMI so it can't change underneath you"
fi

if [ ${#PROBLEMS[@]} -eq 0 ]; then
  echo "preflight [$ENV_NAME]: OK"
  exit 0
fi

if [ "$ENV_NAME" = "prod" ]; then
  echo "preflight [$ENV_NAME]: refusing to plan, replace these first (docs/PRODUCTION.md):" >&2
  printf '  ✗ %s\n' "${PROBLEMS[@]}" >&2
  exit 1
fi

echo "preflight [$ENV_NAME]: WARNING, still using placeholders (fine for a first deploy):"
printf '  ! %s\n' "${PROBLEMS[@]}"
