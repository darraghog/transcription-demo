#!/usr/bin/env bash
# Run application tests: unit tests (pytest) and optionally the full pipeline for an environment.
# Full test: checks an audio source directory for new files, copies them to sample-data, runs pipeline for each.
# Usage: ./scripts/run_tests.sh [OPTIONS] [ENVIRONMENT]
#   --unit-only, -u  Partial: run only unit tests (no AWS, no environment required).
#   ENVIRONMENT      Instance name (default: dev). Used for full test to get BucketName from stack TranscriptionDemoLambda-<env>.
# Optional env: REGION, AWS_PROFILE, AUDIO_SOURCE_DIR (default: /mnt/c/Users/darra/OneDrive/Documents/Audacity).
# Run from transcription-demo repo root. Full test requires AWS CLI + credentials.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

die() { echo "Error: $*" >&2; exit 1; }

# Audio extensions supported by Transcribe (match run_full_pipeline.py)
AUDIO_EXTS=".wav .mp3 .mp4 .m4a .flac .ogg .webm .amr .wma"
AUDIO_SOURCE_DIR="${AUDIO_SOURCE_DIR:-/mnt/c/Users/darra/OneDrive/Documents/Audacity}"
SAMPLE_DATA="$REPO_ROOT/sample-data"

UNIT_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unit-only|-u) UNIT_ONLY=true; shift ;;
    *) break ;;
  esac
done
ENV="${1:-${INSTANCE:-dev}}"
REGION="${REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-PowerUser}"
STACK_NAME="TranscriptionDemoLambda-${ENV}"

if [[ "$UNIT_ONLY" == true ]]; then
  echo "=== Running partial tests (unit only) ==="
else
  echo "=== Running full tests for environment: $ENV ==="
fi
echo ""

echo "1. Unit tests (pytest)..."
uv run pytest tests/ -v
echo ""

if [[ "$UNIT_ONLY" == true ]]; then
  echo "Partial tests passed (unit only)."
  exit 0
fi

echo "2. Full pipeline (audio → Transcribe → Lambda → results)..."
BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --profile "$PROFILE" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text 2>/dev/null || true)
if [[ -z "$BUCKET" || "$BUCKET" == "None" ]]; then
  die "Could not get BucketName from stack $STACK_NAME. Deploy the environment first (e.g. transcription-demo-infra/scripts/bootstrap.sh)."
fi
echo "   Bucket: $BUCKET"
echo ""

# Discover new audio files: in AUDIO_SOURCE_DIR but not yet in sample-data (by basename)
mkdir -p "$SAMPLE_DATA"
NEW_FILES=()
if [[ -d "$AUDIO_SOURCE_DIR" ]]; then
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    if [[ ! -f "$SAMPLE_DATA/$base" ]]; then
      NEW_FILES+=("$f")
    fi
  done < <(find "$AUDIO_SOURCE_DIR" -maxdepth 1 -type f \( -iname "*.wav" -o -iname "*.mp3" -o -iname "*.mp4" -o -iname "*.m4a" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.webm" -o -iname "*.amr" -o -iname "*.wma" \) -print0 2>/dev/null || true)
fi

if [[ ${#NEW_FILES[@]} -eq 0 ]]; then
  echo "   No new audio files in $AUDIO_SOURCE_DIR (or directory not found)."
  echo "   Add files there (e.g. .wav, .mp3) or set AUDIO_SOURCE_DIR to your audio folder."
  echo "   Full test skipped (no files to process)."
  exit 0
fi

echo "   Copying ${#NEW_FILES[@]} new file(s) from $AUDIO_SOURCE_DIR to sample-data/..."
for f in "${NEW_FILES[@]}"; do
  cp "$f" "$SAMPLE_DATA/"
  echo "     $(basename "$f")"
done
echo ""

echo "   Running full pipeline for each new file..."
for f in "${NEW_FILES[@]}"; do
  base=$(basename "$f")
  dest="$SAMPLE_DATA/$base"
  echo "   --- $base ---"
  uv run python scripts/run_full_pipeline.py "$dest" --bucket "$BUCKET" --profile "$PROFILE" --region "$REGION"
  echo ""
done
echo "Full tests passed for environment: $ENV (${#NEW_FILES[@]} file(s) processed)."
