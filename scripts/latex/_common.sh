#!/bin/bash
# Shared helpers for the LaTeX build and release scripts.
# Source it, do not execute it:  source "${SCRIPT_DIR}/_common.sh"

# ---- logging ----
log_info() { echo "ℹ️  $*"; }
log_step() { echo "🔨 $*"; }
log_ok()   { echo "✅ $*"; }
log_warn() { echo "⚠️  $*"; }
log_err()  { echo "❌ $*" >&2; }

die() { log_err "$*"; exit 1; }

# ---- argument parsing ----

# True when the token after a flag is that flag's value rather than the next flag.
# A value can go missing two ways: semantic-release renders an empty
# ${lastRelease.version} as a trailing bare "--last", and a hand-run can put a
# value-less flag ahead of another one. Neither may eat the flag that follows.
has_value() { [[ $# -gt 1 && "$2" != --* ]]; }

# The value of a value-taking flag, empty when it was omitted.
# Use as:  --last) LAST_VERSION="$(flag_value "$@")"; shift "$(value_shift "$@")" ;;
flag_value() { has_value "$@" && printf '%s' "$2"; return 0; }

# How many arguments that flag consumes: itself and its value, or just itself.
value_shift() { has_value "$@" && echo 2 || echo 1; }

# ---- project paths ----

# Sets PROJECT_ROOT (absolute), BUILD_ROOT, DIST_DIR and LOGS_DIR, then cd's to the root.
setup_paths() {
    local root="$1"
    [[ -n "${root}" ]] || die "--root is required"
    [[ -d "${root}" ]] || die "--root is not a directory: ${root}"

    PROJECT_ROOT="$(cd "${root}" && pwd)"
    BUILD_ROOT="${PROJECT_ROOT}/build"
    DIST_DIR="${PROJECT_ROOT}/dist"
    LOGS_DIR="${BUILD_ROOT}/logs"

    mkdir -p "${DIST_DIR}" "${LOGS_DIR}"
    cd "${PROJECT_ROOT}"
}

# Create and echo a per-task sandbox under build/. Everything a task writes that is not
# a publishable artifact stays inside its own sandbox, so tasks never collide and the
# order they run in cannot affect the result.
sandbox_dir() {
    local dir="${BUILD_ROOT}/$1"
    mkdir -p "${dir}"
    printf '%s' "${dir}"
}

# Copy a log out of a sandbox so everything worth reading is together under build/logs/.
collect_log() {
    local src="$1" name="$2"
    [[ -f "${src}" ]] && cp "${src}" "${LOGS_DIR}/${name}"
    return 0
}

# ---- LaTeX ----

require_tool() {
    command -v "$1" &> /dev/null || die "$1 is not installed. See scripts/latex/install_dep.sh"
}

# Copy everything a LaTeX document needs to compile from the project root into a sandbox.
copy_sources() {
    local dest="$1" item
    for item in *.tex *.bib *.bst *.cls *.sty assets chapters bibstyle.json; do
        [[ -e "${item}" ]] || continue
        cp -r "${item}" "${dest}/"
    done
}

# The standard LaTeX incantation: pdflatex, bibtex, pdflatex, pdflatex.
# Only the last pass may fail the script; the earlier ones always report errors that the
# later passes resolve. Run from inside the sandbox.
compile_document() {
    local stem="$1"
    pdflatex -interaction=nonstopmode "${stem}.tex" || true
    bibtex "${stem}" || true
    pdflatex -interaction=nonstopmode "${stem}.tex" || true
    pdflatex -interaction=nonstopmode "${stem}.tex"
}

# Compile a standalone .tex twice (no bibliography); used for the latexdiff output,
# which already carries an inlined bbl. Never fatal: a diff that will not compile is
# reported, not a release blocker.
compile_plain() {
    local stem="$1" log_prefix="$2"
    pdflatex -interaction=nonstopmode "${stem}.tex" > "${log_prefix}1.log" 2>&1 || true
    pdflatex -interaction=nonstopmode "${stem}.tex" > "${log_prefix}2.log" 2>&1 || true
}

# Copy what a latexdiff result needs in order to compile. The diff .tex keeps the original
# document's \documentclass, \usepackage and \includegraphics, so without the project's
# class files, packages and figures it will not build.
copy_diff_resources() {
    local dest="$1" item
    for item in "${PROJECT_ROOT}"/*.cls "${PROJECT_ROOT}"/*.sty "${PROJECT_ROOT}"/*.bst "${PROJECT_ROOT}/assets"; do
        [[ -e "${item}" ]] || continue
        cp -r "${item}" "${dest}/"
    done
}

# Make another document's .aux available in this sandbox, so cross-document references
# (the xr package's \externaldocument) can resolve. The other document must already have
# been compiled once. Its own .aux is never overwritten: a sandbox may still hold a stale
# copy of this document's .aux from an earlier cross-reference round.
copy_aux_from() {
    local other="$1" dest="$2" own_stem="$3" f
    for f in "${BUILD_ROOT}/${other}"/*.aux; do
        [[ -e "${f}" ]] || continue
        [[ "$(basename "${f}")" == "${own_stem}.aux" ]] && continue
        cp "${f}" "${dest}/"
    done
}
