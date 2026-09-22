#!/bin/bash
# Diff a document already built into dist/ against a published release.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ---- defaults ----
ROOT_ARG=""
FROM_NAME=""
COMPARE_VERSION=""
REPO_OWNER=""
REPO_NAME=""
OUTPUT_NAME=""
ASSET_NAME="source"
AUX_FROM=""

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)       ROOT_ARG="$(flag_value "$@")";        shift "$(value_shift "$@")" ;;
        --from)       FROM_NAME="$(flag_value "$@")";       shift "$(value_shift "$@")" ;;
        --compare)    COMPARE_VERSION="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
        --owner)      REPO_OWNER="$(flag_value "$@")";      shift "$(value_shift "$@")" ;;
        --repo)       REPO_NAME="$(flag_value "$@")";       shift "$(value_shift "$@")" ;;
        --output)     OUTPUT_NAME="$(flag_value "$@")";     shift "$(value_shift "$@")" ;;
        --asset-name) ASSET_NAME="$(flag_value "$@")";      shift "$(value_shift "$@")" ;;
        --aux-from)   AUX_FROM="$(flag_value "$@")";        shift "$(value_shift "$@")" ;;
        --help)
            cat <<'EOF'
compare.sh — diff a document already built into dist/ against a published release
Usage: compare.sh --root DIR --from NAME --compare VER --owner OWNER --repo REPO
                  --output NAME [--asset-name NAME] [--aux-from NAME]
  --root DIR         Project root (required)
  --from NAME        Document to diff; reads dist/<NAME>_expanded.tex and dist/<NAME>.bib
  --compare VER      Release tag to compare against, e.g. v1.0.0
  --owner OWNER      Repository owner
  --repo REPO        Repository name
  --output NAME      Sandbox name and the artifact name: dist/<NAME>.pdf
  --asset-name NAME  Release asset to download is <NAME>-<version>.tex (default: source)
  --aux-from NAME    Copy another document's .aux from build/<NAME>/ into the diff
                     sandbox, so cross-document references resolve in the diff too

Run build.sh for the document first; this script never compiles it. When the release
does not carry the asset there is nothing to diff against, so the diff is skipped.
EOF
            exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done

# ---- validate ----
setup_paths "${ROOT_ARG}"
: "${FROM_NAME:?--from is required}"
: "${COMPARE_VERSION:?--compare is required}"
: "${REPO_OWNER:?--owner is required}"
: "${REPO_NAME:?--repo is required}"
: "${OUTPUT_NAME:?--output is required}"

CURRENT_SOURCE="${DIST_DIR}/${FROM_NAME}_expanded.tex"
[[ -f "${CURRENT_SOURCE}" ]] || die "${CURRENT_SOURCE} not found — run build.sh --output-name ${FROM_NAME} first"

require_tool latexdiff

SANDBOX="$(sandbox_dir "${OUTPUT_NAME}")"
COMPARE_FILE="${ASSET_NAME}-${COMPARE_VERSION#[vV]}.tex"

log_info "Diffing ${FROM_NAME} against ${COMPARE_VERSION} of ${REPO_OWNER}/${REPO_NAME}"

# ---- fetch the published side ----
if ! bash "${SCRIPT_DIR}/download-release-file.sh" \
        --owner "${REPO_OWNER}" --repo "${REPO_NAME}" \
        --version "${COMPARE_VERSION}" --asset "${COMPARE_FILE}" \
        --output "${SANDBOX}" \
   || [[ ! -f "${SANDBOX}/${COMPARE_FILE}" ]]; then
    log_warn "${COMPARE_FILE} is not available from ${COMPARE_VERSION} — skipping this diff"
    exit 0
fi

# ---- assemble the diff sandbox ----
# The bibliography comes from dist/, so the diff resolves citations exactly as the
# document did. Fall back to the project's raw .bib when ures-bib was unavailable.
cp "${CURRENT_SOURCE}" "${SANDBOX}/"
if [[ -f "${DIST_DIR}/${FROM_NAME}.bib" ]]; then
    cp "${DIST_DIR}/${FROM_NAME}.bib" "${SANDBOX}/"
else
    cp "${PROJECT_ROOT}"/*.bib "${SANDBOX}/" 2>/dev/null || true
fi
copy_diff_resources "${SANDBOX}"
if [[ -n "${AUX_FROM}" ]]; then
    copy_aux_from "${AUX_FROM}" "${SANDBOX}" "${OUTPUT_NAME}"
fi

cd "${SANDBOX}"

echo "🔍 Generating LaTeX diff..."
if ! latexdiff --flatten -L "$(date)|${COMPARE_VERSION}->current" \
        "${COMPARE_FILE}" "${FROM_NAME}_expanded.tex" > "${OUTPUT_NAME}.tex"; then
    log_warn "latexdiff reported problems; the diff may still be usable"
fi

if ! command -v pdflatex &> /dev/null; then
    log_warn "pdflatex is not available; ${SANDBOX}/${OUTPUT_NAME}.tex was created but not compiled"
    exit 0
fi

echo "📄 Compiling diff PDF..."
compile_plain "${OUTPUT_NAME}" "pdflatex"
collect_log "${SANDBOX}/pdflatex1.log" "${OUTPUT_NAME}-pdflatex1.log"
collect_log "${SANDBOX}/pdflatex2.log" "${OUTPUT_NAME}-pdflatex2.log"

if [[ ! -f "${OUTPUT_NAME}.pdf" ]]; then
    log_warn "diff PDF was not produced; see build/logs/${OUTPUT_NAME}-pdflatex*.log"
    exit 0
fi

cp "${OUTPUT_NAME}.pdf" "${DIST_DIR}/"
log_ok "Diff complete: dist/${OUTPUT_NAME}.pdf"
echo "💡 Added text is blue, deleted text is red with strikethrough"
