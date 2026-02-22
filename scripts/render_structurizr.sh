#!/usr/bin/env bash
#
# Render Structurizr workspace to Mermaid and/or PlantUML using the Structurizr CLI Docker image.
# Run from the transcription-demo repo root.
#
# Usage:
#   ./scripts/render_structurizr.sh [OPTIONS] [WORKSPACE]
#
# Arguments:
#   WORKSPACE   Path to .dsl or .json workspace (default: docs/architecture/workspace.dsl)
#
# Options:
#   -o, --output DIR   Output directory (default: docs/architecture/output)
#   --mermaid          Export only Mermaid
#   --plantuml         Export only PlantUML (C4-PlantUML)
#   --lite             Run Structurizr Lite and open workspace in browser (no export)
#   --no-pull          Skip pulling the Docker image (fail if not present)
#   -h, --help         Show this help and install guidance
#
# Prerequisites:
#   - Docker installed and running. If not:
#     https://docs.docker.com/get-docker/
#   - For export: structurizr/cli image. For --lite: structurizr/lite image.
#     Script will pull the required image by default.
#
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_IMAGE="${STRUCTURIZR_CLI_IMAGE:-structurizr/cli:latest}"
LITE_IMAGE="${STRUCTURIZR_LITE_IMAGE:-structurizr/lite:latest}"
LITE_PORT="${STRUCTURIZR_LITE_PORT:-8080}"
WORKSPACE_ARG=""
OUTPUT_DIR=""
MERMAID_ONLY=false
PLANTUML_ONLY=false
DO_PULL=true
LITE_MODE=false

usage() {
  cat << 'USAGE'
Usage: ./scripts/render_structurizr.sh [OPTIONS] [WORKSPACE]

  WORKSPACE   Path to .dsl or .json workspace (default: docs/architecture/workspace.dsl)
  -o, --output DIR   Output directory (default: docs/architecture/output)
  --mermaid          Export only Mermaid
  --plantuml         Export only PlantUML (C4-PlantUML)
  --lite             Run Structurizr Lite in browser (no export). Ctrl+C to stop.
  --no-pull          Do not pull Docker image (fail if image missing)
  -h, --help         Show this help

Export output:
  Files under OUTPUT_DIR/mermaid/ and OUTPUT_DIR/plantuml/.
  Use Mermaid config "securityLevel": "loose" for .mmd; C4-PlantUML for .puml.

--lite: Opens http://localhost:8080 (or STRUCTURIZR_LITE_PORT) to view/edit the workspace.
  Image: structurizr/lite. Stop with Ctrl+C.

Install guidance (Docker / image not installed):
  1. Install Docker:
     - Linux:   https://docs.docker.com/engine/install/
     - macOS:  https://docs.docker.com/desktop/install/mac-install/
     - Windows: https://docs.docker.com/desktop/install/windows-install/
     Then start Docker Desktop or the daemon (e.g. systemctl start docker).
  2. Pull images (script does this by default):
     docker pull structurizr/cli:latest    # for export
     docker pull structurizr/lite:latest   # for --lite
  3. Run this script again from the repo root.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -o|--output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --mermaid)
      MERMAID_ONLY=true
      shift
      ;;
    --plantuml)
      PLANTUML_ONLY=true
      shift
      ;;
    --lite)
      LITE_MODE=true
      shift
      ;;
    --no-pull)
      DO_PULL=false
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      WORKSPACE_ARG="$1"
      shift
      ;;
  esac
done

WORKSPACE="${WORKSPACE_ARG:-$REPO_ROOT/docs/architecture/workspace.dsl}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/docs/architecture/output}"

# Resolve to absolute paths (realpath -m is GNU; fallback for macOS)
abs_path() {
  local base="$1" path="$2"
  if [[ "$path" == /* ]]; then
    echo "$path"
    return
  fi
  if command -v realpath >/dev/null 2>&1; then
    (cd "$base" && realpath -m "$path" 2>/dev/null) || echo "$base/$path"
  else
    (cd "$base" && cd "$(dirname "$path")" && echo "$(pwd)/$(basename "$path")") 2>/dev/null || echo "$base/$path"
  fi
}
WORKSPACE_ABS="$(abs_path "$REPO_ROOT" "$WORKSPACE")"
OUTPUT_ABS="$(abs_path "$REPO_ROOT" "$OUTPUT_DIR")"

# Ensure workspace and output are under repo (Docker mounts repo root)
case "$WORKSPACE_ABS" in
  "$REPO_ROOT"/*) ;;
  *)
    echo "Error: Workspace path must be under repo root: $REPO_ROOT" >&2
    exit 1
    ;;
esac
case "$OUTPUT_ABS" in
  "$REPO_ROOT"/*) ;;
  *)
    echo "Error: Output path must be under repo root: $REPO_ROOT" >&2
    exit 1
    ;;
esac

if [[ ! -f "$WORKSPACE_ABS" ]]; then
  echo "Error: Workspace file not found: $WORKSPACE_ABS" >&2
  exit 1
fi

# Relative paths for use inside container (mount point = repo root)
WORK_REL="${WORKSPACE_ABS#$REPO_ROOT/}"
OUT_REL="${OUTPUT_ABS#$REPO_ROOT/}"

# --- Docker checks ---
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker is not installed or not on PATH." >&2
  echo "" >&2
  usage >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not running. Start Docker Desktop or run: systemctl start docker" >&2
  exit 1
fi

if [[ "$DO_PULL" == true ]] && [[ "$LITE_MODE" != true ]]; then
  echo "Ensuring Structurizr CLI image is available: $CLI_IMAGE"
  docker pull "$CLI_IMAGE" || {
    echo "Warning: Could not pull $CLI_IMAGE. Trying with existing image." >&2
  }
fi

# --- Structurizr Lite mode ---
if [[ "$LITE_MODE" == true ]]; then
  if [[ "$DO_PULL" == true ]]; then
    echo "Ensuring Structurizr Lite image is available: $LITE_IMAGE"
    docker pull "$LITE_IMAGE" || {
      echo "Warning: Could not pull $LITE_IMAGE. Trying with existing image." >&2
    }
  fi
  if ! docker image inspect "$LITE_IMAGE" >/dev/null 2>&1; then
    echo "Error: Docker image not found: $LITE_IMAGE" >&2
    echo "Pull it with: docker pull structurizr/lite:latest" >&2
    exit 1
  fi
  # Lite expects workspace in mounted dir. Mount repo root; set path/filename so Lite finds the file.
  WORKSPACE_DIR_REL="${WORK_REL%/*}"
  WORKSPACE_BASE="${WORK_REL##*/}"
  WORKSPACE_FILENAME="${WORKSPACE_BASE%.*}"
  LITE_URL="http://localhost:${LITE_PORT}"
  echo "Starting Structurizr Lite with workspace: $WORK_REL"
  echo "  Open in browser: $LITE_URL"
  echo "  Stop with Ctrl+C"
  (
    sleep 2
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$LITE_URL" 2>/dev/null || true
    elif command -v open >/dev/null 2>&1; then
      open "$LITE_URL" 2>/dev/null || true
    fi
  ) &
  LITE_ENV=()
  [[ -n "$WORKSPACE_DIR_REL" ]] && LITE_ENV+=(-e "STRUCTURIZR_WORKSPACE_PATH=$WORKSPACE_DIR_REL")
  [[ "$WORKSPACE_FILENAME" != "workspace" ]] && LITE_ENV+=(-e "STRUCTURIZR_WORKSPACE_FILENAME=$WORKSPACE_FILENAME")
  docker run --rm -it \
    -p "${LITE_PORT}:8080" \
    -v "$REPO_ROOT:/usr/local/structurizr" \
    "${LITE_ENV[@]}" \
    "$LITE_IMAGE"
  exit 0
fi

# --- Export mode: require CLI image ---
if ! docker image inspect "$CLI_IMAGE" >/dev/null 2>&1; then
  echo "Error: Docker image not found: $CLI_IMAGE" >&2
  echo "Pull it with: docker pull structurizr/cli:latest" >&2
  exit 1
fi

# --- Export ---
mkdir -p "$OUTPUT_ABS"
EXPORT_MERMAID=false
EXPORT_PLANTUML=false
if [[ "$MERMAID_ONLY" == true ]]; then
  EXPORT_MERMAID=true
elif [[ "$PLANTUML_ONLY" == true ]]; then
  EXPORT_PLANTUML=true
else
  EXPORT_MERMAID=true
  EXPORT_PLANTUML=true
fi

run_export() {
  local format="$1"
  local subdir="$2"
  local out_sub="$OUT_REL/$subdir"
  mkdir -p "$REPO_ROOT/$out_sub"
  echo "Exporting to $format -> $out_sub"
  docker run --rm \
    -v "$REPO_ROOT:/workspace:ro" \
    -v "$REPO_ROOT/$out_sub:/out:rw" \
    -w /workspace \
    "$CLI_IMAGE" export \
    -workspace "$WORK_REL" \
    -format "$format" \
    -output /out
}

if [[ "$EXPORT_MERMAID" == true ]]; then
  run_export "mermaid" "mermaid"
fi
if [[ "$EXPORT_PLANTUML" == true ]]; then
  run_export "plantuml/c4plantuml" "plantuml"
fi

echo "Done. Output under: $OUTPUT_ABS"
[[ "$EXPORT_MERMAID" == true ]] && echo "  - Mermaid:   $OUTPUT_ABS/mermaid/"
[[ "$EXPORT_PLANTUML" == true ]] && echo "  - PlantUML:  $OUTPUT_ABS/plantuml/"
echo "Use Mermaid config {\"securityLevel\": \"loose\"} for .mmd; use C4-PlantUML includes for .puml."
