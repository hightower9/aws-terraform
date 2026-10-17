#!/bin/bash
set -euo pipefail

# Create the S3 buckets that hold Terraform state. Bucket names and region
# are read from environments/<env>/backend.tfbackend, so renaming a bucket
# there is all it takes. Locking uses S3 lockfiles (use_lockfile), so no
# DynamoDB table is needed. Safe to re-run.
#
# Usage:
#   AWS_PROFILE=prod-admin ./scripts/bootstrap-state.sh prod   # one env
#   ./scripts/bootstrap-state.sh                              # dev uat prod
#   (via make: make bootstrap-state [ENVS="dev uat"] [EMULATOR=1])

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ $# -gt 0 ]; then
  ENVIRONMENTS=("$@")
elif [ -n "${AWS_ENDPOINT_URL:-}" ]; then
  ENVIRONMENTS=(local dev uat prod)   # emulator: local too
else
  ENVIRONMENTS=(dev uat prod)
fi

backend_value() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$2" | head -1
}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "=== Bootstrapping Terraform state buckets ==="
echo "Account: $ACCOUNT_ID${AWS_ENDPOINT_URL:+ (emulator: $AWS_ENDPOINT_URL)}"

for ENV in "${ENVIRONMENTS[@]}"; do
  FILE="$ROOT/environments/$ENV/backend.tfbackend"
  [ -f "$FILE" ] || { echo "ERROR: $FILE not found" >&2; exit 1; }
  if [ "$ENV" = "local" ] && [ -z "${AWS_ENDPOINT_URL:-}" ]; then
    echo "Skipping local: it only exists on the emulator."
    continue
  fi

  BUCKET=$(backend_value bucket "$FILE")
  REGION=$(backend_value region "$FILE")

  if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "[$ENV] Bucket $BUCKET already exists."
    continue
  fi

  echo "[$ENV] Creating s3://$BUCKET in $REGION"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi

  aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"},"BucketKeyEnabled":true}]}'

  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,BlockPublicPolicy=true,IgnorePublicAcls=true,RestrictPublicBuckets=true

  aws s3api put-bucket-policy --bucket "$BUCKET" --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"DenyInsecureTransport\",
      \"Effect\": \"Deny\",
      \"Principal\": \"*\",
      \"Action\": \"s3:*\",
      \"Resource\": [\"arn:aws:s3:::$BUCKET\", \"arn:aws:s3:::$BUCKET/*\"],
      \"Condition\": {\"Bool\": {\"aws:SecureTransport\": \"false\"}}
    }]
  }"

  aws s3api put-bucket-tagging --bucket "$BUCKET" \
    --tagging "TagSet=[{Key=ManagedBy,Value=terraform},{Key=Purpose,Value=tf-state},{Key=Environment,Value=$ENV}]"

  echo "[$ENV] Bucket $BUCKET ready."
done

echo ""
echo "=== Bootstrap complete ==="
echo "Next: make init ENV=<env>${AWS_ENDPOINT_URL:+ EMULATOR=1}"
