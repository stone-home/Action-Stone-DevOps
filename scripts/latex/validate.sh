#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- defaults ----
PROJECT_ROOT=""
MAIN_FILE="${MAIN_FILE:-main}"

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)     PROJECT_ROOT="$2"; shift 2 ;;
        --filename) MAIN_FILE="$2";    shift 2 ;;
        --help)
            cat <<'EOF'
validate.sh — check project structure (main file exists)
Usage: validate.sh --root DIR [--filename NAME]
  --root DIR        Project root (required)
  --filename NAME   Main file name (default: main)
EOF
            exit 0 ;;
        *) echo "❌ unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ---- validate ----
: "${PROJECT_ROOT:?--root is required}"
cd "${PROJECT_ROOT}"

echo "✔️ Validating LaTeX project..."

if [ ! -f "${MAIN_FILE}.tex" ]; then
    echo "❌ ${MAIN_FILE}.tex not found"
    exit 1
fi

echo "✅ Validation complete"
