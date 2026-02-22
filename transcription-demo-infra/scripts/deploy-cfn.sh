#!/usr/bin/env bash
# Deploy transcription-demo infra using CloudFormation.
# Prereqs: bundle and upload Lambda code (see README). Set CODE_BUCKET, CODE_S3_KEY; optionally INSTANCE, REGION, AWS_PROFILE.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CF_DIR="$REPO_ROOT/cloudformation"
INSTANCE="${INSTANCE:-dev}"
REGION="${REGION:-us-east-1}"

die() { echo "Error: $*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || die "Install AWS CLI."
[ -f "$CF_DIR/infra-stack.yaml" ] && [ -f "$CF_DIR/lambda-stack.yaml" ] || die "CloudFormation templates not found; run from repo root."
aws sts get-caller-identity >/dev/null 2>&1 || die "Configure AWS credentials (e.g. AWS_PROFILE or aws configure)."

INFRA_STACK="TranscriptionDemoInfra-${INSTANCE}"
LAMBDA_STACK="TranscriptionDemoLambda-${INSTANCE}"

# CODE_BUCKET: use infra stack output if not set (code bucket is created by infra stack)
if [ -z "${CODE_BUCKET}" ]; then
  CODE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$INFRA_STACK" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='CodeBucketName'].OutputValue" --output text 2>/dev/null) || true
fi
[ -n "${CODE_BUCKET}" ] && [ -n "${CODE_S3_KEY}" ] || die "Set CODE_BUCKET and CODE_S3_KEY (run scripts/bundle_lambda.sh then scripts/upload_lambda_zip.sh). Or deploy infra stack first so CODE_BUCKET is available from stack output."

echo "Deploying infra stack: $INFRA_STACK"
aws cloudformation deploy \
  --template-file "$CF_DIR/infra-stack.yaml" \
  --stack-name "$INFRA_STACK" \
  --parameter-overrides "Instance=$INSTANCE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --no-fail-on-empty-changeset

ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "$INFRA_STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='SummarizeRoleArn'].OutputValue" --output text)
echo "SummarizeRoleArn: $ROLE_ARN"

echo "Deploying Lambda stack: $LAMBDA_STACK"
aws cloudformation deploy \
  --template-file "$CF_DIR/lambda-stack.yaml" \
  --stack-name "$LAMBDA_STACK" \
  --parameter-overrides \
    "Instance=$INSTANCE" \
    "SummarizeRoleArn=$ROLE_ARN" \
    "CodeS3Bucket=$CODE_BUCKET" \
    "CodeS3Key=$CODE_S3_KEY" \
    "Region=$REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --no-fail-on-empty-changeset

BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name "$LAMBDA_STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)
LAMBDA_NAME=$(aws cloudformation describe-stack-resources --stack-name "$LAMBDA_STACK" --region "$REGION" \
  --query "StackResources[?ResourceType=='AWS::Lambda::Function'].PhysicalResourceId" --output text)
LAMBDA_ARN=$(aws lambda get-function --function-name "$LAMBDA_NAME" --region "$REGION" --query 'Configuration.FunctionArn' --output text 2>/dev/null || true)
echo "BucketName: $BUCKET_NAME"
echo "Lambda ARN: $LAMBDA_ARN"

if [[ -n "$BUCKET_NAME" && -n "$LAMBDA_ARN" && "$BUCKET_NAME" != "None" ]]; then
  echo ""
  echo "Adding S3→Lambda trigger..."
  BUCKET_NAME="$BUCKET_NAME" LAMBDA_ARN="$LAMBDA_ARN" REGION="$REGION" bash "$SCRIPT_DIR/add_s3_trigger.sh"
  echo "Trigger configured. Demo bucket ready: $BUCKET_NAME"
else
  echo ""
  echo "Add S3 trigger manually (one-time):"
  echo "  BUCKET_NAME=$BUCKET_NAME LAMBDA_ARN=<Lambda ARN> REGION=$REGION $SCRIPT_DIR/add_s3_trigger.sh"
fi
