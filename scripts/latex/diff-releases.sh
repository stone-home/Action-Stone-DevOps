#!/bin/bash
# Diff two published releases against each other. A manual tool: it downloads both
# sides and never looks at the working tree.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ---- defaults ----
ROOT_ARG=""
OLD_VERSION=""
NEW_VERSION=""
REPO_OWNER=""
REPO_NAME=""
OUTPUT_NAME=""
ASSET_NAME="source"

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)       ROOT_ARG="$(flag_value "$@")";    shift "$(value_shift "$@")" ;;
        --owner)      REPO_OWNER="$(flag_value "$@")";  shift "$(value_shift "$@")" ;;
        --repo)       REPO_NAME="$(flag_value "$@")";   shift "$(value_shift "$@")" ;;
        --old)        OLD_VERSION="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
        --new)        NEW_VERSION="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
        --asset-name) ASSET_NAME="$(flag_value "$@")";  shift "$(value_shift "$@")" ;;
        --output)     OUTPUT_NAME="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
        --help)
            cat <<'EOF'
diff-releases.sh — diff two published releases against each other
Usage: diff-releases.sh --root DIR --owner OWNER --repo REPO --old VER --new VER
                        [--asset-name NAME] [--output NAME]
  --root DIR         Project root (required); output lands in <root>/dist/
  --owner OWNER      Repository owner
  --repo REPO        Repository name
  --old VER          Older release tag, e.g. v1.0.0
  --new VER          Newer release tag, e.g. v1.1.0
  --asset-name NAME  Asset to download is <NAME>-<version>.tex (default: source).
                     Pass appendix-source to diff appendices.
  --output NAME      Artifact name (default: diff-<old>-to-<new>)

Needs GITHUB_TOKEN and jq. The working tree is never touched.
EOF
            exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done

# ---- validate ----
setup_paths "${ROOT_ARG}"
: "${REPO_OWNER:?--owner is required}"
: "${REPO_NAME:?--repo is required}"
: "${OLD_VERSION:?--old is required}"
: "${NEW_VERSION:?--new is required}"
: "${OUTPUT_NAME:=diff-${OLD_VERSION}-to-${NEW_VERSION}}"

require_tool latexdiff

SANDBOX="$(sandbox_dir "${OUTPUT_NAME}")"
OLD_FILE="${ASSET_NAME}-${OLD_VERSION#[vV]}.tex"
NEW_FILE="${ASSET_NAME}-${NEW_VERSION#[vV]}.tex"

log_info "Diffing ${OLD_VERSION} → ${NEW_VERSION} of ${REPO_OWNER}/${REPO_NAME}"

download_asset() {
    local version="$1" asset="$2"
    bash "${SCRIPT_DIR}/download-release-file.sh" \
        --owner "${REPO_OWNER}" --repo "${REPO_NAME}" \
        --version "${version}" --asset "${asset}" --output "${SANDBOX}"
    [[ -f "${SANDBOX}/${asset}" ]] || die "could not download ${asset} from ${version}"
}

download_asset "${OLD_VERSION}" "${OLD_FILE}"
download_asset "${NEW_VERSION}" "${NEW_FILE}"

# The published sources carry an inlined bibliography, but still reference the project's
# class files, packages and figures.
copy_diff_resources "${SANDBOX}"

cd "${SANDBOX}"

echo "🔍 Generating LaTeX diff..."
if ! latexdiff --flatten -L "${OLD_VERSION}->${NEW_VERSION}" \
        "${OLD_FILE}" "${NEW_FILE}" > "${OUTPUT_NAME}.tex"; then
    log_warn "latexdiff reported problems; the diff may still be usable"
fi

require_tool pdflatex
echo "📄 Compiling diff PDF..."
compile_plain "${OUTPUT_NAME}" "pdflatex"
collect_log "${SANDBOX}/pdflatex1.log" "${OUTPUT_NAME}-pdflatex1.log"
collect_log "${SANDBOX}/pdflatex2.log" "${OUTPUT_NAME}-pdflatex2.log"

[[ -f "${OUTPUT_NAME}.pdf" ]] || die "diff PDF was not produced; see build/logs/${OUTPUT_NAME}-pdflatex*.log"

cp "${OUTPUT_NAME}.pdf" "${DIST_DIR}/"
log_ok "Diff complete: dist/${OUTPUT_NAME}.pdf"
