#!/usr/bin/env bash
# Verify deployment: get bucket from CloudFormation stack output, run transcript-only demo, assert results file appears.
# Run from transcription-demo-infra. Requires AWS credentials and a deployed stack.
set -e

PROFILE="${AWS_PROFILE:-administrator}"
INSTANCE="${INSTANCE:-dev}"
STACK_NAME="TranscriptionDemoLambda-${INSTANCE}"

echo "Getting bucket name from stack ${STACK_NAME}..."
BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --profile "$PROFILE" --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text 2>/dev/null || true)
if [[ -z "$BUCKET" || "$BUCKET" == "None" ]]; then
  echo "Error: Could not get BucketName output from stack $STACK_NAME. Is it deployed? Run scripts/deploy-cfn.sh (after bundle + upload)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Demo app lives at repo root (transcription-demo); infra is transcription-demo-infra/ inside it
DEMO_DIR="${DEMO_DIR:-$(cd "$INFRA_DIR/.." 2>/dev/null && pwd)}"
if [[ -z "$DEMO_DIR" || ! -d "$DEMO_DIR" ]]; then
  echo "Error: transcription-demo repo root not found at $INFRA_DIR/.. Set DEMO_DIR or run from repo root." >&2
  exit 1
fi

echo "Running transcript-only demo against bucket: $BUCKET"
cd "$DEMO_DIR"
uv run python scripts/run_transcript_only.py --bucket "$BUCKET" --profile "$PROFILE" --wait-seconds 45
echo "Verification passed: Lambda wrote results file to the bucket."
