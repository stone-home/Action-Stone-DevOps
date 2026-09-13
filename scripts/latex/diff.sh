#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- defaults ----
PROJECT_ROOT=""
OLD_FILE=""
NEW_FILE=""

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) PROJECT_ROOT="$2"; shift 2 ;;
        --old)  OLD_FILE="$2";     shift 2 ;;
        --new)  NEW_FILE="$2";     shift 2 ;;
        --help)
            cat <<'EOF'
diff.sh — compare two local .tex versions, produce a latexdiff PDF
Usage: diff.sh --root DIR --old NAME --new NAME
  --root DIR   Project root (required)
  --old NAME   Old main file name (without extension)
  --new NAME   New main file name (without extension)
EOF
            exit 0 ;;
        *) echo "❌ unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ---- validate ----
: "${PROJECT_ROOT:?--root is required}"
: "${OLD_FILE:?--old is required}"
: "${NEW_FILE:?--new is required}"
cd "${PROJECT_ROOT}"

BUILD_DIR="${PROJECT_ROOT}/build"
DIST_DIR="${PROJECT_ROOT}/dist"
REPORT_FILE_NAME="diff_report"

echo "✨ Generating expanded files for ${OLD_FILE} using build.sh..."
bash "${SCRIPT_DIR}/build.sh" --root "${PROJECT_ROOT}" --filename "${OLD_FILE}"

echo "✨ Generating expanded files for ${NEW_FILE} using build.sh..."
bash "${SCRIPT_DIR}/build.sh" --root "${PROJECT_ROOT}" --filename "${NEW_FILE}"

# Check if the two expanded .tex files exist
if [ ! -f "${DIST_DIR}/${OLD_FILE}_expanded.tex" ] || [ ! -f "${DIST_DIR}/${NEW_FILE}_expanded.tex" ]; then
    echo "❌ Error: Expanded .tex file not found. Please ensure build.sh ran correctly and generated the files."
    exit 1
fi

echo "🔍 Comparing the two expanded .tex files..."
latexdiff --flatten -L label "${BUILD_DIR}/${OLD_FILE}_expanded.tex" "${BUILD_DIR}/${NEW_FILE}_expanded.tex" > "${BUILD_DIR}/${REPORT_FILE_NAME}.tex"
if [ $? -ne 0 ]; then
    echo "❌ Error: latexdiff failed to generate the diff."
    exit 1
fi

cp "${BUILD_DIR}/${REPORT_FILE_NAME}.tex" "${DIST_DIR}/"

# Compile the wrapper file with pdflatex to generate the PDF
cd "${DIST_DIR}"
pdflatex -interaction=nonstopmode "${REPORT_FILE_NAME}.tex" || true
pdflatex -interaction=nonstopmode "${REPORT_FILE_NAME}.tex"

echo "✅ Diff report PDF generated successfully: ${DIST_DIR}/${REPORT_FILE_NAME}.pdf"
echo "🎉 Script execution complete!"
