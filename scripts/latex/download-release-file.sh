#!/bin/bash
# Download one asset from a GitHub release.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ---- defaults ----
REPO_OWNER=""
REPO_NAME=""
VERSION=""
ASSET_NAME=""
OUTPUT_PATH="."

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --owner)   REPO_OWNER="$(flag_value "$@")";  shift "$(value_shift "$@")" ;;
        --repo)    REPO_NAME="$(flag_value "$@")";   shift "$(value_shift "$@")" ;;
        --version) VERSION="$(flag_value "$@")";     shift "$(value_shift "$@")" ;;
        --asset)   ASSET_NAME="$(flag_value "$@")";  shift "$(value_shift "$@")" ;;
        --output)  OUTPUT_PATH="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
        --help)
            cat <<'EOF'
download-release-file.sh — download an asset from a GitHub release
Usage: download-release-file.sh --owner OWNER --repo REPO --version VER --asset NAME [--output DIR]
  --owner OWNER    Repository owner
  --repo REPO      Repository name
  --version VER    Release tag, or 'latest' for the newest release
  --asset NAME     Asset file name to download
  --output DIR     Output directory (default: current directory)
Requires jq, and GITHUB_TOKEN for private repos and rate limits.
EOF
            exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done

# ---- validate ----
: "${REPO_OWNER:?--owner is required}"
: "${REPO_NAME:?--repo is required}"
: "${VERSION:?--version is required}"
: "${ASSET_NAME:?--asset is required}"

require_tool jq

echo "🚀 Downloading '${ASSET_NAME}' from release ${VERSION} of ${REPO_OWNER}/${REPO_NAME}..."

if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_warn "GITHUB_TOKEN is not set; proceeding unauthenticated. This may fail on private repos or rate limits."
fi

if [ "${VERSION}" == "latest" ]; then
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
else
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${VERSION}"
fi
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN:-}"

CURL_OUTPUT=$(curl -sSL -w "%{http_code}" -H "Accept: application/vnd.github.v3+json" -H "${AUTH_HEADER}" "${API_URL}")
HTTP_STATUS=$(echo "${CURL_OUTPUT}" | tail -n1)
RESPONSE=$(echo "${CURL_OUTPUT}" | sed '$d')

[ "${HTTP_STATUS}" == "404" ] && die "release '${VERSION}' not found"

ASSET_ID=$(echo "${RESPONSE}" | jq --raw-output ".assets[]? | select(.name == \"${ASSET_NAME}\") | .id")
if [ -z "${ASSET_ID}" ] || [ "${ASSET_ID}" == "null" ]; then
    die "asset '${ASSET_NAME}' is not attached to release ${VERSION}"
fi

echo "🔍 Found asset ID ${ASSET_ID}, downloading..."
curl -sSL -H "Accept: application/octet-stream" \
     -H "${AUTH_HEADER}" \
     -o "${OUTPUT_PATH}/${ASSET_NAME}" \
     -L "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/assets/${ASSET_ID}"

log_ok "Saved to ${OUTPUT_PATH}/${ASSET_NAME}"
