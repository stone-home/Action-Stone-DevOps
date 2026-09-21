#!/bin/bash
# Sanity-check a LaTeX project before building it.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ---- defaults ----
ROOT_ARG=""
MAIN_FILE="${MAIN_FILE:-main}"

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)     ROOT_ARG="$(flag_value "$@")";  shift "$(value_shift "$@")" ;;
        --filename) MAIN_FILE="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
        --help)
            cat <<'EOF'
validate.sh — check project structure (the main file exists)
Usage: validate.sh --root DIR [--filename NAME]
  --root DIR        Project root (required)
  --filename NAME   Source file name without extension (default: main)
EOF
            exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done

# ---- validate ----
setup_paths "${ROOT_ARG}"
: "${MAIN_FILE:?--filename cannot be empty}"

echo "✔️  Validating LaTeX project..."
[[ -f "${MAIN_FILE}.tex" ]] || die "${MAIN_FILE}.tex not found in ${PROJECT_ROOT}"
log_ok "Validation complete"
