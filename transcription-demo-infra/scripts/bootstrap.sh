#!/usr/bin/env bash
# Bootstrap an environment: bundle Lambda, upload to S3, deploy Infra + Lambda stacks.
# Usage: ./scripts/bootstrap.sh [ENVIRONMENT]
#   ENVIRONMENT  Instance name (e.g. dev, prod). Default: dev.
# Run from any directory. Requires: bash, AWS CLI + credentials, Python 3 + pip or uv, zip or Python 3.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

die() { echo "Error: $*" >&2; exit 1; }

# Environment (instance name): first argument or default dev
INSTANCE="${1:-dev}"

REGION="${REGION:-us-east-1}"
if [ -z "${CODE_BUCKET}" ]; then
  CODE_BUCKET=genai-training-bucket
  echo "Using CODE_BUCKET=$CODE_BUCKET (set CODE_BUCKET to override)."
fi
export INSTANCE REGION CODE_BUCKET

# Pre-flight: required tools and layout
command -v aws >/dev/null 2>&1 || die "Install AWS CLI (https://aws.amazon.com/cli/)."
aws sts get-caller-identity >/dev/null 2>&1 || die "Configure AWS credentials (e.g. AWS_PROFILE or aws configure)."
PYTHON=""
for p in python3 python; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys; sys.exit(0 if sys.version_info.major >= 3 else 1)' 2>/dev/null; then
    PYTHON="$p"
    break
  fi
done
[ -n "$PYTHON" ] || die "Install Python 3."
if ! command -v uv >/dev/null 2>&1; then
  "$PYTHON" -m pip --version >/dev/null 2>&1 || die "Install pip (e.g. $PYTHON -m ensurepip) or uv."
fi
command -v zip >/dev/null 2>&1 || "$PYTHON" -c "import zipfile" 2>/dev/null || die "Install zip or Python 3 (for packaging Lambda)."
[ -d "$REPO_ROOT/lambda" ] && [ -f "$REPO_ROOT/lambda/lambda_function.py" ] || die "Run from repo root; lambda/ must contain lambda_function.py."
[ -f "$REPO_ROOT/lambda/requirements.txt" ] || die "lambda/requirements.txt not found."

echo "=== Bootstrapping environment: instance=$INSTANCE, region=$REGION ==="
echo ""

echo "1. Bundling Lambda..."
bash scripts/bundle_lambda.sh

echo ""
echo "2. Uploading Lambda zip to s3://${CODE_BUCKET}/..."
upload_out=$(CODE_BUCKET="$CODE_BUCKET" bash scripts/upload_lambda_zip.sh)
echo "$upload_out"
CODE_S3_KEY=$(echo "$upload_out" | grep '^CODE_S3_KEY=' | cut -d= -f2-)
if [ -z "$CODE_S3_KEY" ]; then
  echo "Failed to get CODE_S3_KEY from upload script." >&2
  exit 1
fi
export CODE_S3_KEY

echo ""
echo "3. Deploying Infra + Lambda stacks..."
bash scripts/deploy-cfn.sh

echo ""
echo "4. Adding S3→Lambda trigger..."
BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name "TranscriptionDemoLambda-${INSTANCE}" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)
LAMBDA_NAME=$(aws cloudformation describe-stack-resources --stack-name "TranscriptionDemoLambda-${INSTANCE}" --region "$REGION" \
  --query "StackResources[?ResourceType=='AWS::Lambda::Function'].PhysicalResourceId" --output text)
LAMBDA_ARN=$(aws lambda get-function --function-name "$LAMBDA_NAME" --region "$REGION" --query 'Configuration.FunctionArn' --output text 2>/dev/null || true)
if [[ -n "$BUCKET_NAME" && -n "$LAMBDA_ARN" && "$BUCKET_NAME" != "None" ]]; then
  BUCKET_NAME="$BUCKET_NAME" LAMBDA_ARN="$LAMBDA_ARN" REGION="$REGION" bash scripts/add_s3_trigger.sh
  echo "Trigger configured."
else
  echo "  Run manually: BUCKET_NAME=$BUCKET_NAME LAMBDA_ARN=$LAMBDA_ARN REGION=$REGION bash scripts/add_s3_trigger.sh"
fi
echo ""
echo "Bootstrap complete (instance=$INSTANCE). Use --bucket $BUCKET_NAME with the demo scripts."
