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
build.sh — compile the LaTeX document; output goes to <root>/dist/
Usage: build.sh --root DIR [--filename NAME]
  --root DIR        Project root (required), where main.tex lives
  --filename NAME   Main file name without extension (default: main)

When ures-bib is available: full compile with the original .bib (to write .aux),
then format cited entries to a new file, replace the build copy, and compile again.
EOF
            exit 0 ;;
        *) echo "❌ unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ---- validate ----
: "${PROJECT_ROOT:?--root is required}"
cd "${PROJECT_ROOT}"

BUILD_DIR="${PROJECT_ROOT}/build"
DIST_DIR="${PROJECT_ROOT}/dist"

compile_pdf() {
    pdflatex -interaction=nonstopmode "${MAIN_FILE}.tex" || true
    bibtex "${MAIN_FILE}" || true
    pdflatex -interaction=nonstopmode "${MAIN_FILE}.tex" || true
    pdflatex -interaction=nonstopmode "${MAIN_FILE}.tex"
}

echo "🔨 Building LaTeX document..."
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

# Copy files to build directory
cp -r *.tex "${BUILD_DIR}/" 2>/dev/null || true
cp -r *.bib "${BUILD_DIR}/" 2>/dev/null || true
cp -r *.cls "${BUILD_DIR}/" 2>/dev/null || true
cp -r *.sty "${BUILD_DIR}/" 2>/dev/null || true
cp -r assets "${BUILD_DIR}/" 2>/dev/null || true
cp -r chapters "${BUILD_DIR}/" 2>/dev/null || true

cd "${BUILD_DIR}"

echo "📄 Pass 1: compile with original bibliography..."
compile_pdf

if command -v ures-bib &> /dev/null && [[ -f "${MAIN_FILE}.aux" ]]; then
    if [[ -f "${PROJECT_ROOT}/bibstyle.json" ]]; then
        cp "${PROJECT_ROOT}/bibstyle.json" "${BUILD_DIR}/"
    fi
    shopt -s nullglob
    bibs=( *.bib )
    shopt -u nullglob
    formatted_any=0
    for bib in "${bibs[@]}"; do
        [[ "${bib}" == *.formatted.bib ]] && continue
        out="${bib%.bib}.formatted.bib"
        echo "📚 Formatting ${bib} with ures-bib (--aux ${MAIN_FILE}.aux)..."
        ures-bib format "${bib}" \
            --aux "${MAIN_FILE}.aux" \
            --output "${out}" \
            --profile "${BIB_PROFILE:-library}"
        cp "${out}" "${DIST_DIR}/${bib}"
        cp "${out}" "${bib}"
        formatted_any=1
    done
    if [[ "${formatted_any}" -eq 1 ]]; then
        echo "📄 Pass 2: compile with formatted bibliography..."
        compile_pdf
    fi
fi

# Generate expanded TeX
if command -v latexpand &> /dev/null; then
    latexpand --expand-bbl "${MAIN_FILE}.bbl" "${MAIN_FILE}.tex" > "${MAIN_FILE}"_expanded.tex
else
    cp "${MAIN_FILE}.tex" "${MAIN_FILE}"_expanded.tex
fi

# Copy to dist
cd ..
cp "${BUILD_DIR}/${MAIN_FILE}.pdf" "${DIST_DIR}/"
cp "${BUILD_DIR}/${MAIN_FILE}.bbl" "${DIST_DIR}/" 2>/dev/null || touch "${DIST_DIR}/${MAIN_FILE}.bbl"
cp "${BUILD_DIR}/${MAIN_FILE}"_expanded.tex "${DIST_DIR}/"

echo "✅ Build complete!"
