#!/usr/bin/env bash
# Remove all resources for an environment (instance): Lambda stack, then Infra stack.
# The Infra stack's code bucket has DeletionPolicy: Retain; optionally empty and delete it for full cleanup.
# Usage: REGION=<region> [INSTANCE=<name>] ./scripts/teardown.sh [INSTANCE]
#   REGION   Required unless AWS_DEFAULT_REGION is set.
#   INSTANCE Optional. Instance name (default: dev). Pass as first arg or env.
#   DELETE_CODE_BUCKET If set (e.g. 1 or true), empty and delete the code bucket after deleting stacks.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

die() { echo "Error: $*" >&2; exit 1; }

INSTANCE="${1:-${INSTANCE:-dev}}"
REGION="${REGION:-${AWS_DEFAULT_REGION}}"
[ -n "$REGION" ] || die "Set REGION (e.g. export REGION=us-east-1) or AWS_DEFAULT_REGION."

command -v aws >/dev/null 2>&1 || die "Install AWS CLI."
aws sts get-caller-identity >/dev/null 2>&1 || die "Configure AWS credentials (e.g. AWS_PROFILE or aws configure)."

LAMBDA_STACK="TranscriptionDemoLambda-${INSTANCE}"
INFRA_STACK="TranscriptionDemoInfra-${INSTANCE}"

echo "=== Teardown environment: instance=$INSTANCE, region=$REGION ==="
echo ""

# 1. Delete Lambda stack first (transcript bucket, Lambda, permissions)
if aws cloudformation describe-stacks --stack-name "$LAMBDA_STACK" --region "$REGION" >/dev/null 2>&1; then
  echo "1. Deleting Lambda stack: $LAMBDA_STACK"
  aws cloudformation delete-stack --stack-name "$LAMBDA_STACK" --region "$REGION"
  echo "   Waiting for stack delete to complete..."
  aws cloudformation wait stack-delete-complete --stack-name "$LAMBDA_STACK" --region "$REGION"
  echo "   Deleted $LAMBDA_STACK"
else
  echo "1. Lambda stack $LAMBDA_STACK does not exist (skipping)"
fi
echo ""

# 2. Delete Infra stack (IAM role; code bucket is retained)
if aws cloudformation describe-stacks --stack-name "$INFRA_STACK" --region "$REGION" >/dev/null 2>&1; then
  echo "2. Deleting Infra stack: $INFRA_STACK"
  aws cloudformation delete-stack --stack-name "$INFRA_STACK" --region "$REGION"
  echo "   Waiting for stack delete to complete..."
  aws cloudformation wait stack-delete-complete --stack-name "$INFRA_STACK" --region "$REGION"
  echo "   Deleted $INFRA_STACK (code bucket retained by CloudFormation)"
else
  echo "2. Infra stack $INFRA_STACK does not exist (skipping)"
fi
echo ""

# 3. Optionally empty and delete the code bucket (left behind due to Retain)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CODE_BUCKET="code-bucket-${INSTANCE}-${ACCOUNT_ID}"
if [[ -n "${DELETE_CODE_BUCKET}" && "${DELETE_CODE_BUCKET}" != "0" && "${DELETE_CODE_BUCKET}" != "false" ]]; then
  if aws s3api head-bucket --bucket "$CODE_BUCKET" 2>/dev/null; then
    echo "3. Emptying and deleting code bucket: $CODE_BUCKET"
    aws s3 rm "s3://${CODE_BUCKET}/" --recursive --region "$REGION" 2>/dev/null || true
    aws s3 rb "s3://${CODE_BUCKET}" --region "$REGION" 2>/dev/null || die "Failed to delete bucket $CODE_BUCKET (empty it manually if needed)."
    echo "   Deleted $CODE_BUCKET"
  else
    echo "3. Code bucket $CODE_BUCKET does not exist (skipping)"
  fi
else
  echo "3. Code bucket $CODE_BUCKET retained (set DELETE_CODE_BUCKET=1 to empty and delete it)"
fi
echo ""
echo "Teardown complete (instance=$INSTANCE)."
