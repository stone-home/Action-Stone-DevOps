#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- defaults ----
REPO_OWNER=""
REPO_NAME=""
VERSION=""
ASSET_NAME=""
OUTPUT_PATH="."

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --owner)   REPO_OWNER="$2";  shift 2 ;;
        --repo)    REPO_NAME="$2";   shift 2 ;;
        --version) VERSION="$2";     shift 2 ;;
        --asset)   ASSET_NAME="$2";  shift 2 ;;
        --output)  OUTPUT_PATH="$2"; shift 2 ;;
        --help)
            cat <<'EOF'
download-release-file.sh — download an asset from a GitHub release
Usage: download-release-file.sh --owner OWNER --repo REPO --version VER --asset NAME [--output DIR]
  --owner OWNER    Repository owner
  --repo REPO      Repository name
  --version VER    Release tag (without 'v' prefix; 'latest' for newest)
  --asset NAME     Asset file name to download
  --output DIR     Output directory (default: current directory)
Requires GITHUB_TOKEN env var (for private repos / rate limits)
EOF
            exit 0 ;;
        *) echo "❌ unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ---- validate ----
: "${REPO_OWNER:?--owner is required}"
: "${REPO_NAME:?--repo is required}"
: "${VERSION:?--version is required}"
: "${ASSET_NAME:?--asset is required}"

echo "🚀 Attempting to download '${ASSET_NAME}' from release ${VERSION} of ${REPO_OWNER}/${REPO_NAME}..."

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "❌ Error: 'jq' is not installed. Please install it (e.g., sudo apt-get install jq)."
    exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "⚠️ Warning: GITHUB_TOKEN not set. Proceeding without authentication. This may fail on private repos or due to rate limits."
fi

# Get the release asset ID from the GitHub API
if [ "${VERSION}" == "latest" ]; then
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
else
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${VERSION}"
fi
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN:-}"
CURL_OUTPUT=$(curl -sSL -w "%{http_code}" -H "Accept: application/vnd.github.v3+json" -H "${AUTH_HEADER}" "${API_URL}")

HTTP_STATUS=$(echo "${CURL_OUTPUT}" | tail -n1)
RESPONSE=$(echo "${CURL_OUTPUT}" | sed '$d')

if [ "${HTTP_STATUS}" == "404" ]; then
    echo "❌ Error: Release for version '${VERSION}' not found."
    exit 1
fi

ASSET_ID=$(echo "${RESPONSE}" | jq --raw-output ".assets[]? | select(.name == \"${ASSET_NAME}\") | .id")

if [ -z "${ASSET_ID}" ] || [ "${ASSET_ID}" == "null" ]; then
    echo "❌ Error: Asset '${ASSET_NAME}' not found for version v${VERSION}."
    exit 1
fi

echo "🔍 Found asset ID: ${ASSET_ID}. Downloading..."
DOWNLOAD_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/assets/${ASSET_ID}"
curl -sSL -H "Accept: application/octet-stream" \
     -H "${AUTH_HEADER}" \
     -o "${OUTPUT_PATH}/${ASSET_NAME}" \
     -L "${DOWNLOAD_URL}"

echo "✅ Download successful! File saved to ${OUTPUT_PATH}/${ASSET_NAME}"
