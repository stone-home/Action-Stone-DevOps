#!/bin/bash
# Compile one LaTeX document into <root>/dist/.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ---- defaults ----
ROOT_ARG=""
MAIN_FILE="${MAIN_FILE:-main}"
OUTPUT_NAME=""
BIB_NAME=""

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)        ROOT_ARG="$(flag_value "$@")";    shift "$(value_shift "$@")" ;;
        --filename)    MAIN_FILE="$(flag_value "$@")";   shift "$(value_shift "$@")" ;;
        --output-name) OUTPUT_NAME="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
        --bib)         BIB_NAME="$(flag_value "$@")";    shift "$(value_shift "$@")" ;;
        --help)
            cat <<'EOF'
build.sh — compile one LaTeX document; artifacts go to <root>/dist/
Usage: build.sh --root DIR [--filename NAME] [--output-name NAME] [--bib NAME]
  --root DIR          Project root (required), where the .tex lives
  --filename NAME     Source file name without extension (default: main)
  --output-name NAME  Base name for the build/ sandbox and every dist/ artifact
                      (default: same as --filename)
  --bib NAME          Bibliography to format, without extension. By default it is
                      read from \bibdata{} in the document's .aux.

Artifacts: dist/<output-name>.pdf, .bbl, .bib and <output-name>_expanded.tex.
Everything else stays in build/<output-name>/.

When ures-bib is available: compile once with the original .bib to write the .aux,
format the entries the document actually cites, then compile again.
EOF
            exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done

# ---- validate ----
setup_paths "${ROOT_ARG}"
: "${MAIN_FILE:?--filename cannot be empty}"
: "${OUTPUT_NAME:=${MAIN_FILE}}"
[[ -f "${MAIN_FILE}.tex" ]] || die "${MAIN_FILE}.tex not found in ${PROJECT_ROOT}"

SANDBOX="$(sandbox_dir "${OUTPUT_NAME}")"

# Bibliographies this document cites, as "<name>.bib", taken from \bibdata{foo,bar}
# in the .aux that the first pass writes.
bibs_from_aux() {
    local aux="$1" line inner name
    BIBS=()
    while IFS= read -r line; do
        inner="${line#*\\bibdata\{}"
        inner="${inner%%\}*}"
        inner="${inner// /}"
        IFS=',' read -ra names <<< "${inner}"
        for name in "${names[@]}"; do
            [[ -z "${name}" ]] && continue
            BIBS+=("${name}.bib")
        done
    done < <(grep -oE '\\bibdata\{[^}]+\}' "${aux}" || true)
}

log_step "Building ${MAIN_FILE}.tex → dist/${OUTPUT_NAME}.pdf"
copy_sources "${SANDBOX}"
cd "${SANDBOX}"

echo "📄 Pass 1: compile with the original bibliography..."
compile_document "${MAIN_FILE}"

# ---- format the bibliography down to the entries this document cites ----
if command -v ures-bib &> /dev/null && [[ -f "${MAIN_FILE}.aux" ]]; then
    if [[ -n "${BIB_NAME}" ]]; then
        BIBS=("${BIB_NAME}.bib")
    else
        bibs_from_aux "${MAIN_FILE}.aux"
    fi

    # All of this document's bibliographies are published as one dist/<output-name>.bib.
    # It is assembled in the sandbox and only copied out once every entry formatted
    # cleanly, so a failed run never leaves a truncated bibliography in dist/.
    combined="${OUTPUT_NAME}.combined.bib"
    : > "${combined}"

    for bib in "${BIBS[@]}"; do
        [[ -f "${bib}" ]] || die "bibliography ${bib} was not found in ${PROJECT_ROOT}"
        formatted="${bib%.bib}.formatted.bib"
        echo "📚 Formatting ${bib} with ures-bib (--aux ${MAIN_FILE}.aux)..."
        ures-bib format "${bib}" \
            --aux "${MAIN_FILE}.aux" \
            --output "${formatted}" \
            --profile "${BIB_PROFILE:-library}"
        cat "${formatted}" >> "${combined}"
        cp "${formatted}" "${bib}"
    done

    if [[ ${#BIBS[@]} -gt 0 ]]; then
        cp "${combined}" "${DIST_DIR}/${OUTPUT_NAME}.bib"
        echo "📄 Pass 2: compile with the formatted bibliography..."
        compile_document "${MAIN_FILE}"
    fi
fi

# ---- expanded single-file source ----
# latexpand inlines the .bbl, so it is only asked to do that when one exists: a document
# without a bibliography produces no .bbl and latexpand would fail on the missing file.
if command -v latexpand &> /dev/null && [[ -f "${MAIN_FILE}.bbl" ]]; then
    latexpand --expand-bbl "${MAIN_FILE}.bbl" "${MAIN_FILE}.tex" > "${MAIN_FILE}_expanded.tex"
elif command -v latexpand &> /dev/null; then
    latexpand "${MAIN_FILE}.tex" > "${MAIN_FILE}_expanded.tex"
else
    cp "${MAIN_FILE}.tex" "${MAIN_FILE}_expanded.tex"
fi

# ---- publish ----
# Sandbox files are named after the source stem; dist/ artifacts after --output-name.
cp "${MAIN_FILE}.pdf" "${DIST_DIR}/${OUTPUT_NAME}.pdf"
cp "${MAIN_FILE}.bbl" "${DIST_DIR}/${OUTPUT_NAME}.bbl" 2>/dev/null || touch "${DIST_DIR}/${OUTPUT_NAME}.bbl"
cp "${MAIN_FILE}_expanded.tex" "${DIST_DIR}/${OUTPUT_NAME}_expanded.tex"

collect_log "${SANDBOX}/${MAIN_FILE}.log" "${OUTPUT_NAME}.log"
collect_log "${SANDBOX}/${MAIN_FILE}.blg" "${OUTPUT_NAME}.blg"

log_ok "Build complete: dist/${OUTPUT_NAME}.pdf"
