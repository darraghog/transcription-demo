#!/usr/bin/env bash
# Bootstrap an environment: deploy Infra stack (creates code bucket + IAM role), bundle Lambda, upload to code bucket, deploy Lambda stack.
# Usage: REGION=<region> [INSTANCE=<name>] ./scripts/bootstrap.sh [INSTANCE]
#   REGION   Required unless AWS_DEFAULT_REGION is set. AWS region (e.g. us-east-1).
#   INSTANCE Optional. Instance name for stack names (default: dev). Pass as first arg or env.
# Code bucket is created by the Infra stack (CloudFormation); name: code-bucket-<INSTANCE>-<account-id>.
# Run from any directory. Requires: bash, AWS CLI + credentials, Python 3 + pip or uv, zip or Python 3.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

die() { echo "Error: $*" >&2; exit 1; }

# Instance: first argument, or INSTANCE env, or dev
INSTANCE="${1:-${INSTANCE:-dev}}"
# Region: explicit REGION or AWS_DEFAULT_REGION
REGION="${REGION:-${AWS_DEFAULT_REGION}}"
[ -n "$REGION" ] || die "Set REGION (e.g. export REGION=us-east-1) or AWS_DEFAULT_REGION."
export INSTANCE REGION

# Pre-flight: required tools and credentials
command -v aws >/dev/null 2>&1 || die "Install AWS CLI (https://aws.amazon.com/cli/)."
aws sts get-caller-identity >/dev/null 2>&1 || die "Configure AWS credentials (e.g. AWS_PROFILE or aws configure)."

# 1. Deploy infra stack first (creates code bucket + IAM role)
echo "=== Bootstrapping environment: instance=$INSTANCE, region=$REGION ==="
echo ""
echo "1. Deploying Infra stack (code bucket + IAM role)..."
INFRA_STACK="TranscriptionDemoInfra-${INSTANCE}"
aws cloudformation deploy \
  --template-file "$REPO_ROOT/cloudformation/infra-stack.yaml" \
  --stack-name "$INFRA_STACK" \
  --parameter-overrides "Instance=$INSTANCE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --no-fail-on-empty-changeset

# Get code bucket name from infra stack output
INFRA_STACK="TranscriptionDemoInfra-${INSTANCE}"
CODE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$INFRA_STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='CodeBucketName'].OutputValue" --output text 2>/dev/null) || die "Could not get CodeBucketName from stack $INFRA_STACK."
export CODE_BUCKET

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
LAMBDA_SRC="${LAMBDA_SRC:-$REPO_ROOT/../lambda-src}"
[ -d "$LAMBDA_SRC" ] && [ -f "$LAMBDA_SRC/lambda_function.py" ] || die "Run from transcription-demo-infra; repo root must contain lambda-src/ with lambda_function.py."
[ -f "$LAMBDA_SRC/requirements.txt" ] || die "lambda-src/requirements.txt not found."

echo ""
echo "2. Bundling Lambda..."
bash scripts/bundle_lambda.sh

echo ""
echo "3. Uploading Lambda zip to s3://${CODE_BUCKET}/..."
upload_out=$(CODE_BUCKET="$CODE_BUCKET" bash scripts/upload_lambda_zip.sh)
echo "$upload_out"
CODE_S3_KEY=$(echo "$upload_out" | grep '^CODE_S3_KEY=' | cut -d= -f2-)
if [ -z "$CODE_S3_KEY" ]; then
  echo "Failed to get CODE_S3_KEY from upload script." >&2
  exit 1
fi
export CODE_S3_KEY

echo ""
echo "4. Deploying Lambda stack..."
bash scripts/deploy-cfn.sh

echo ""
echo "5. Adding S3→Lambda trigger..."
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
