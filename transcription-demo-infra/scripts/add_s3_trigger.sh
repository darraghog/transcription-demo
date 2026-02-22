#!/usr/bin/env bash
# Add S3 event notification (.json -> Lambda) after CloudFormation deploy.
# CloudFormation cannot add this in-template due to circular dependency; run once after lambda-stack deploy.
# Usage: BUCKET_NAME=<name> LAMBDA_ARN=<arn> [REGION=...] [AWS_PROFILE=...] ./scripts/add_s3_trigger.sh
set -e
die() { echo "Error: $*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || die "Install AWS CLI."
[ -n "${BUCKET_NAME}" ] && [ -n "${LAMBDA_ARN}" ] || die "Set BUCKET_NAME and LAMBDA_ARN (from stack outputs)."

CONFIG=$(cat <<EOF
{
  "LambdaFunctionConfigurations": [
    {
      "Id": "TranscriptionDemoSummarize",
      "LambdaFunctionArn": "${LAMBDA_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [{"Name": "suffix", "Value": ".json"}]
        }
      }
    }
  ]
}
EOF
)
REGION="${REGION:-${AWS_DEFAULT_REGION}}"
if [ -n "$REGION" ]; then
  aws s3api put-bucket-notification-configuration --bucket "$BUCKET_NAME" --notification-configuration "$CONFIG" --region "$REGION"
else
  aws s3api put-bucket-notification-configuration --bucket "$BUCKET_NAME" --notification-configuration "$CONFIG"
fi
echo "S3 trigger added: $BUCKET_NAME -> $LAMBDA_ARN (.json)"
