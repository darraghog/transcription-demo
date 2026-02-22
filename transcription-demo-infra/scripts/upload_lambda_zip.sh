#!/usr/bin/env bash
# Zip .lambda_bundle and upload to S3 for CloudFormation Lambda deployment.
# Usage: CODE_BUCKET=my-bucket [CODE_PREFIX=lambda/] ./scripts/upload_lambda_zip.sh
# Outputs: CODE_S3_KEY=<key> for use as CodeS3Key parameter.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/.lambda_bundle"
ZIP="$REPO_ROOT/.lambda_bundle.zip"

die() { echo "Error: $*" >&2; exit 1; }

[ -n "${CODE_BUCKET}" ] || die "Set CODE_BUCKET to the S3 bucket that will hold the Lambda zip (e.g. your deployment bucket)."
[ -f "$BUNDLE_DIR/lambda_function.py" ] || die "Run scripts/bundle_lambda.sh first."

# Need zip or Python 3 for packaging
PYTHON=""
if ! command -v zip >/dev/null 2>&1; then
  for p in python3 python; do
    if command -v "$p" >/dev/null 2>&1 && "$p" -c "import zipfile" 2>/dev/null; then
      PYTHON="$p"
      break
    fi
  done
  [ -n "$PYTHON" ] || die "Install zip or Python 3 to create the Lambda package."
fi

command -v aws >/dev/null 2>&1 || die "Install AWS CLI."

CODE_PREFIX="${CODE_PREFIX:-lambda/}"
CODE_S3_KEY="${CODE_PREFIX}transcription-demo-summarize-$(date +%Y%m%d%H%M%S).zip"
if command -v zip >/dev/null 2>&1; then
  ( cd "$BUNDLE_DIR" && zip -rq "$ZIP" . )
else
  BUNDLE_DIR="$BUNDLE_DIR" ZIP="$ZIP" "$PYTHON" -c "
import zipfile, os
bundle = os.environ['BUNDLE_DIR']
out = os.environ['ZIP']
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zf:
  for root, _, files in os.walk(bundle):
    for f in files:
      path = os.path.join(root, f)
      arcname = os.path.relpath(path, bundle)
      zf.write(path, arcname)
"
fi
aws s3 cp "$ZIP" "s3://${CODE_BUCKET}/${CODE_S3_KEY}"
rm -f "$ZIP"
echo "Uploaded to s3://${CODE_BUCKET}/${CODE_S3_KEY}"
echo "CODE_S3_KEY=${CODE_S3_KEY}"
