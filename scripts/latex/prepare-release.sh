#!/bin/bash
# Called by the semantic-release prepare step: build every document, then diff each one
# against the previous release. Everything publishable ends up in <root>/dist/.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ---- defaults ----
ROOT_ARG=""
LAST_VERSION=""
MAIN_FILE="${MAIN_FILE:-main}"
APPENDIX_FILE=""

# ---- parse ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)     ROOT_ARG="$(flag_value "$@")";      shift "$(value_shift "$@")" ;;
        --last)     LAST_VERSION="$(flag_value "$@")";  shift "$(value_shift "$@")" ;;
        --main)     MAIN_FILE="$(flag_value "$@")";     shift "$(value_shift "$@")" ;;
        --appendix) APPENDIX_FILE="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
        --help)
            cat <<'EOF'
prepare-release.sh — build the release artifacts and the diffs against the last release
Usage: prepare-release.sh --root DIR [--last VERSION] [--main NAME] [--appendix NAME]
  --root DIR        Project root (required)
  --last VERSION    Previous released version; when given, also produce the diffs.
                    semantic-release fills this from ${lastRelease.version}. You can
                    also pass it by hand (--last 0.9.0) to diff against any published
                    version. Omit it, or pass "null", to skip the diffs entirely.
  --main NAME       Main document source file without extension (default: main)
  --appendix NAME   Appendix document source file without extension. Omit it and no
                    appendix is built; give it and <NAME>.tex must exist.

Produces in dist/:
  main.pdf  main.bbl  main.bib  main_expanded.tex
  appendix.pdf  appendix.bbl  appendix.bib  appendix_expanded.tex   (with --appendix)
  diff.pdf  appendix-diff.pdf                                       (with --last)
EOF
            exit 0 ;;
        --next)
            # Removed: the version was never used here. Kept as a named case so an
            # out-of-date .releaserc gets an actionable message instead of "unknown arg".
            die "--next was removed; drop it from prepareCmd in .releaserc" ;;
        *) die "unknown arg: $1" ;;
    esac
done

# ---- validate ----
setup_paths "${ROOT_ARG}"
: "${MAIN_FILE:?--main cannot be empty}"

if [[ -n "${APPENDIX_FILE}" && ! -f "${APPENDIX_FILE}.tex" ]]; then
    die "--appendix was given but ${APPENDIX_FILE}.tex was not found in ${PROJECT_ROOT}"
fi

# GitHub Actions sets these automatically.
REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-}"
REPO_NAME="${GITHUB_REPOSITORY#*/}"

has_previous_release() {
    [[ -n "${LAST_VERSION}" && "${LAST_VERSION}" != "null" ]]
}

# The diffs download the previous release, so they need to know which repository.
if has_previous_release && [[ -z "${REPO_OWNER}" || -z "${REPO_NAME}" ]]; then
    die "--last needs GITHUB_REPOSITORY_OWNER and GITHUB_REPOSITORY; GitHub Actions sets them, so export them by hand when running this locally"
fi

# Both documents are compiled once before either is finalised. That order matters: the
# xr package resolves \externaldocument against the other document's .aux, which only
# exists after that document has been built. A single pass over each in turn would leave
# every cross-document reference undefined.

build_document() {
    bash "${SCRIPT_DIR}/build.sh" --root "${PROJECT_ROOT}" "$@"
}

# ---- 1. main document ----
build_document --filename "${MAIN_FILE}" --output-name main

# ---- 2. appendix ----
if [[ -n "${APPENDIX_FILE}" ]]; then
    build_document --filename "${APPENDIX_FILE}" --output-name appendix

    # ---- 3. rebuild both, now that each can see the other's .aux ----
    log_info "Resolving cross-document references"
    build_document --filename "${MAIN_FILE}"     --output-name main     --aux-from appendix
    build_document --filename "${APPENDIX_FILE}" --output-name appendix --aux-from main
fi

# ---- 4. diff the main document ----
if has_previous_release; then
    bash "${SCRIPT_DIR}/compare.sh" \
        --root "${PROJECT_ROOT}" \
        --from main \
        --compare "v${LAST_VERSION}" \
        --owner "${REPO_OWNER}" \
        --repo "${REPO_NAME}" \
        --output diff \
        ${APPENDIX_FILE:+--aux-from appendix}
fi

# ---- 5. diff the appendix ----
# A release made before the appendix existed carries no appendix-source asset, so a
# missing one is expected rather than fatal.
if has_previous_release && [[ -n "${APPENDIX_FILE}" ]]; then
    bash "${SCRIPT_DIR}/compare.sh" \
        --root "${PROJECT_ROOT}" \
        --from appendix \
        --compare "v${LAST_VERSION}" \
        --owner "${REPO_OWNER}" \
        --repo "${REPO_NAME}" \
        --output appendix-diff \
        --asset-name appendix-source \
        --aux-from main \
        --allow-missing
fi

log_ok "Release prepared. Artifacts in ${DIST_DIR}, logs in ${LOGS_DIR}"
