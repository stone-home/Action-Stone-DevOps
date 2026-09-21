#!/bin/bash
# LaTeX Document Diff Comparison Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- defaults ----
PROJECT_ROOT=""
CURRENT_VERSION=""
COMPARE_VERSION=""
REPO_OWNER=""
REPO_NAME=""
OUTPUT_NAME=""

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)    PROJECT_ROOT="$2";    shift 2 ;;
        --current) CURRENT_VERSION="$2"; shift 2 ;;
        --compare) COMPARE_VERSION="$2"; shift 2 ;;
        --owner)   REPO_OWNER="$2";      shift 2 ;;
        --repo)    REPO_NAME="$2";       shift 2 ;;
        --output)  OUTPUT_NAME="$2";     shift 2 ;;
        --help)
            cat <<'EOF'
compare.sh — compare two release versions (or current source vs a version), produce a diff PDF
Usage: compare.sh --root DIR --current VER --compare VER --owner OWNER --repo REPO [--output NAME]
  --root DIR       Project root (required)
  --current VER    Current version; pass "null" to build from local source
  --compare VER    Older version to compare against
  --owner OWNER    Repository owner
  --repo REPO      Repository name
  --output NAME    Output file name (default: diff-<compare>-to-<current>)
EOF
            exit 0 ;;
        *) echo "❌ unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ---- validate ----
: "${PROJECT_ROOT:?--root is required}"
: "${CURRENT_VERSION:?--current is required}"
: "${COMPARE_VERSION:?--compare is required}"
: "${REPO_OWNER:?--owner is required}"
: "${REPO_NAME:?--repo is required}"
: "${OUTPUT_NAME:=diff-${COMPARE_VERSION}-to-${CURRENT_VERSION}}"
cd "${PROJECT_ROOT}"

echo "📊 Starting diff comparison..."
echo "Current version: ${CURRENT_VERSION}"
echo "Compare version: ${COMPARE_VERSION}"
echo "Repository: ${REPO_OWNER}/${REPO_NAME}"

WORK_DIR="${PROJECT_ROOT}/dist"
mkdir -p "${WORK_DIR}"

echo "📦 Working in directory: $(pwd)"

# Function to download release file
download_release_file() {
    local repo_owner=$1
    local repo_name=$2
    local version=$3
    local filename=$4
    local output_dir=$5

    echo "Downloading ${filename} from ${repo_owner}/${repo_name} version ${version}..."

    bash "${SCRIPT_DIR}/download-release-file.sh" \
        --owner "${repo_owner}" --repo "${repo_name}" \
        --version "${version}" --asset "${filename}" --output "${output_dir}" || return 1

    if [ -f "${output_dir}/${filename}" ]; then
        echo "✅ Successfully downloaded ${filename}"
        return 0
    else
        echo "❌ Failed to download ${filename}"
        return 1
    fi
}

# File names
CURRENT_FILE="source-${CURRENT_VERSION#[vV]}.tex"
COMPARE_FILE="source-${COMPARE_VERSION#[vV]}.tex"
DIFF_FILE="${OUTPUT_NAME}.tex"
DIFF_PDF="${OUTPUT_NAME}.pdf"
LOG_FILE="${WORK_DIR}/compare.log"

echo "📥 Preparing All Comparisons..."

if [ "${CURRENT_VERSION}" = "null" ]; then
    echo "⚠️ Current version is 'null', using local source file for comparison"
    echo "🔄 Building current version file (main_expanded.tex)..."
    if ! bash "${SCRIPT_DIR}/build.sh" --root "${PROJECT_ROOT}" > "${LOG_FILE}" 2>&1; then
        echo "❌ build.sh failed. Dump of ${LOG_FILE}:" >&2
        cat "${LOG_FILE}" >&2 || true
        exit 1
    fi
    CURRENT_FILE="main_expanded.tex"
else
    echo "🔄 Preparing current version file (${CURRENT_FILE})..."
    if ! download_release_file "${REPO_OWNER}" "${REPO_NAME}" "${CURRENT_VERSION}" "${CURRENT_FILE}" "${WORK_DIR}"; then
        echo "❌ Failed to download current version file (${CURRENT_FILE})"
        exit 1
    fi
fi

echo "🔄 Preparing comparison version file (${COMPARE_FILE})..."
if ! download_release_file "${REPO_OWNER}" "${REPO_NAME}" "${COMPARE_VERSION}" "${COMPARE_FILE}" "${WORK_DIR}"; then
    echo "❌ Failed to download comparison version file (${COMPARE_FILE})"
    exit 1
fi

echo "📝 All files prepared successfully!"

if [ "${CURRENT_VERSION}" = "null" ]; then
    echo "📊 Comparing: ${COMPARE_VERSION} → current source"
else
    echo "📊 Comparing: ${COMPARE_VERSION} → ${CURRENT_VERSION}"
fi

if ! command -v latexdiff &> /dev/null; then
    echo "❌ latexdiff is not installed. Please install it first."
    echo "ℹ️ Additionally, the install_dep.sh is provided to install dependencies"
    echo "💡 You can install it via your package manager:"
    echo "1. On Ubuntu/Debian: sudo apt-get install latexdiff"
    echo "2. On macOS: brew install texlive"
    exit 1
fi

# Generate diff
# Do not overwrite a .bib that build.sh already placed in dist/ (formatted).
for bib in *.bib; do
    [[ -f "${bib}" ]] || continue
    [[ -e "${WORK_DIR}/${bib}" ]] && continue
    cp "${bib}" "${WORK_DIR}/"
done
cp -r *.cls "${WORK_DIR}/" 2>/dev/null || true
cp -r *.sty "${WORK_DIR}/" 2>/dev/null || true
cp -r assets "${WORK_DIR}/" 2>/dev/null || true
cd "${WORK_DIR}"
echo "🔍 Generating LaTeX diff..."
if latexdiff --flatten -L "$(date)|${COMPARE_VERSION}->${CURRENT_VERSION}" "${COMPARE_FILE}" "${CURRENT_FILE}" > "${DIFF_FILE}"; then
    echo "✅ LaTeX diff generated successfully!"
else
    echo "⚠️  Warning: latexdiff encountered some issues, but diff file may still be usable"
fi

if ! command -v pdflatex &> /dev/null; then
    echo "⚠️  pdflatex is not available. Diff LaTeX file created but PDF will not be generated."
    echo "LaTeX diff file: $(pwd)/${DIFF_FILE}"
else
    echo "📄 Compiling diff PDF..."
    pdflatex -interaction=nonstopmode "${DIFF_FILE}" > pdflatex1.log 2>&1 || true
    pdflatex -interaction=nonstopmode "${DIFF_FILE}" > pdflatex2.log 2>&1 || true
    if [ -f "${DIFF_PDF}" ]; then
        echo "🎉 Diff PDF generated successfully!"
        echo "📄 PDF file: $(pwd)/${DIFF_PDF}"
    else
        echo "⚠️  Diff PDF was not generated (pdflatex failed). See pdflatex1.log / pdflatex2.log"
    fi
fi

# Summary
echo ""
echo "📋 Summary:"
echo "  Working directory: $(pwd)"
echo "  LaTeX diff file: ${DIFF_FILE}"
if [ -f "${DIFF_PDF}" ]; then
    echo "  PDF diff file: ${DIFF_PDF}"
fi

cd ..

echo "  Log files: pdflatex1.log, pdflatex2.log (if PDF generation was attempted)"
echo ""
echo "✅ Diff comparison completed!"
echo "💡 Tip: Added text appears in blue, deleted text appears in red with strikethrough"
