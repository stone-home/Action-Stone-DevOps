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

if command -v ures-bib &> /dev/null; then
    if [[ -f "${PROJECT_ROOT}/bibstyle.json" ]]; then
        cp "${PROJECT_ROOT}/bibstyle.json" "${BUILD_DIR}/"
    fi
    shopt -s nullglob
    for bib in *.bib; do
        echo "📚 Formatting ${bib} with ures-bib..."
        ures-bib format "${bib}" --profile "${BIB_PROFILE:-library}"
    done
    shopt -u nullglob
fi

# Compile PDF
pdflatex -interaction=nonstopmode "${MAIN_FILE}.tex" || true
bibtex "${MAIN_FILE}" || true
pdflatex -interaction=nonstopmode "${MAIN_FILE}.tex" || true
pdflatex -interaction=nonstopmode "${MAIN_FILE}.tex"

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
