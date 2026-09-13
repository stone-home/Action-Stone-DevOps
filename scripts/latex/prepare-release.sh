#!/bin/bash
# The script is only used in Git Action
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- defaults ----
PROJECT_ROOT=""
NEXT_VERSION=""
LAST_VERSION=""

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) PROJECT_ROOT="$2"; shift 2 ;;
        --next) NEXT_VERSION="$2"; shift 2 ;;
        --last) LAST_VERSION="$2"; shift 2 ;;
        --help)
            cat <<'EOF'
prepare-release.sh — called by semantic-release prepare step; builds artifacts + diff
Usage: prepare-release.sh --root DIR --next VERSION [--last VERSION]
  --root DIR        Project root (required)
  --next VERSION    Version about to be released
  --last VERSION    Previous version (if present, also produce a diff)
EOF
            exit 0 ;;
        *) echo "❌ unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ---- validate ----
: "${PROJECT_ROOT:?--root is required}"
: "${NEXT_VERSION:?--next is required}"
cd "${PROJECT_ROOT}"

# GitHub Actions sets these environment variables automatically
REPO_OWNER="${GITHUB_REPOSITORY_OWNER}"
REPO_NAME="${GITHUB_REPOSITORY#*/}"

# Generate diff if previous version exists
if [ -n "${LAST_VERSION}" ] && [ "${LAST_VERSION}" != "null" ]; then
    bash "${SCRIPT_DIR}/compare.sh" \
        --root "${PROJECT_ROOT}" \
        --current "null" \
        --compare "v${LAST_VERSION}" \
        --owner "${REPO_OWNER}" \
        --repo "${REPO_NAME}" \
        --output "diff"
else
    bash "${SCRIPT_DIR}/build.sh" --root "${PROJECT_ROOT}"
fi

echo "✅ Release prepared!"
