#!/usr/bin/env bash
# Bundle Lambda code + dependencies for CloudFormation deploy. Run before upload_lambda_zip.sh when Lambda code or deps change.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Single Lambda source: app’s lambda-src (infra is transcription-demo-infra/ inside repo root)
LAMBDA_SRC="${LAMBDA_SRC:-$REPO_ROOT/../lambda-src}"
BUNDLE_DIR="$REPO_ROOT/.lambda_bundle"

die() { echo "Error: $*" >&2; exit 1; }

# Resolve Python 3
PYTHON=""
for p in python3 python; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys; sys.exit(0 if sys.version_info.major >= 3 else 1)' 2>/dev/null; then
    PYTHON="$p"
    break
  fi
done
[ -n "$PYTHON" ] || die "Python 3 required. Install Python 3."

# Require pip or uv
if ! command -v uv >/dev/null 2>&1; then
  "$PYTHON" -m pip --version >/dev/null 2>&1 || die "Install pip (e.g. $PYTHON -m ensurepip) or uv."
fi

# Require lambda-src layout (repo root is parent of transcription-demo-infra)
[ -d "$LAMBDA_SRC" ] || die "lambda-src not found at $LAMBDA_SRC. Run from transcription-demo-infra (repo root must contain lambda-src)."
[ -f "$LAMBDA_SRC/lambda_function.py" ] || die "lambda-src/lambda_function.py not found."
[ -f "$LAMBDA_SRC/requirements.txt" ] || die "lambda-src/requirements.txt not found."

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
cp -r "$LAMBDA_SRC"/* "$BUNDLE_DIR/"
if command -v uv >/dev/null 2>&1; then
  uv pip install -r "$BUNDLE_DIR/requirements.txt" --target "$BUNDLE_DIR" --quiet
else
  "$PYTHON" -m pip install -r "$BUNDLE_DIR/requirements.txt" -t "$BUNDLE_DIR" --quiet
fi
rm -f "$BUNDLE_DIR/requirements.txt"
echo "Lambda bundle ready at $BUNDLE_DIR"
