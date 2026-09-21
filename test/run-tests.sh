#!/usr/bin/env bash
#
# Smoke-test suite for scripts/latex/.
#
# Run it with:  bash test/run-tests.sh
#
# Every test copies test/fixtures/paper into its own mktemp working copy, so tests
# cannot leak state into each other and nothing is ever written under fixtures/.
# Tests whose toolchain is missing are skipped, not failed; the suite exits non-zero
# only when a test that could run actually failed.
#
# Environment:
#   KEEP_WORKDIRS=1   keep the temporary working copies for inspection
#
# The fixture is deliberately awkward: main.tex loads a local package (fixture.sty),
# styled.tex selects a local bibliography style (fixturestyle.bst), and the project has
# an assets/ directory. A document like that only builds and only diffs if the scripts
# carry the project's own class, package, style and asset files into their sandboxes,
# so T10, T11 and T15 fail if that copying regresses.
#
# Required toolchain: pdflatex, bibtex, latexdiff, latexpand
# Optional toolchain: ures-bib (bibliography filtering), jq (release downloads)
# The GitHub releases API is served by test/stubs/curl from a local directory; the
# suite never touches the network.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
SCRIPTS="${REPO_ROOT}/scripts/latex"
FIXTURE="${TEST_DIR}/fixtures/paper"
STUBS="${TEST_DIR}/stubs"

# Convenience: a TinyTeX install is not on PATH by default.
for _d in "${HOME}"/.TinyTeX/bin/*/; do
    [[ -d "${_d}" ]] && PATH="${_d%/}:${PATH}"
done
export PATH

FAKE_OWNER="fixture-owner"
FAKE_REPO="fixture-repo"

# ---------------------------------------------------------------- reporting ----

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_TESTS=()

pass() { printf 'PASS: %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
skip() { printf 'SKIP: %s -- needs %s\n' "$1" "$2"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
fail() {
    printf 'FAIL: %s -- %s\n' "$1" "$2"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_TESTS+=("$1")
}

# ---------------------------------------------------------------- toolchain ----

have() { command -v "$1" > /dev/null 2>&1; }

missing_tools() {
    local t out=""
    for t in "$@"; do
        have "${t}" || out="${out}${out:+, }${t}"
    done
    printf '%s' "${out}"
}

# ------------------------------------------------------------- working copies --

WORKDIRS=()
WORKDIR=""

# Sets WORKDIR to a fresh working copy of the fixture. It assigns a global rather than
# echoing the path, because a command substitution would run it in a subshell and the
# directory would never make it into WORKDIRS for cleanup.
new_workdir() {
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/latex-smoke.XXXXXXXX")" || return 1
    cp -r "${FIXTURE}/." "${WORKDIR}/"
    WORKDIRS+=("${WORKDIR}")
}

cleanup() {
    if [[ -n "${KEEP_WORKDIRS:-}" ]]; then
        printf '\nKEEP_WORKDIRS is set; working copies left behind:\n'
        printf '  %s\n' "${WORKDIRS[@]:-(none)}"
        return
    fi
    (( ${#WORKDIRS[@]} )) && rm -rf "${WORKDIRS[@]}"
    return 0
}
trap cleanup EXIT

# Run a script inside a working copy, capturing stdout+stderr into <dir>/_run.log.
# Returns the script's exit status.
run_in() {
    local dir="$1"; shift
    ( cd "${dir}" && "$@" ) > "${dir}/_run.log" 2>&1
}

# Same, but with the curl test double in front of PATH and the fake release store
# pointed at <dir>/_releases.
run_in_stubbed() {
    local dir="$1"; shift
    (
        cd "${dir}" || exit 1
        PATH="${STUBS}:${PATH}" \
        STUB_RELEASES="${dir}/_releases" \
        GITHUB_REPOSITORY_OWNER="${FAKE_OWNER}" \
        GITHUB_REPOSITORY="${FAKE_OWNER}/${FAKE_REPO}" \
        "$@"
    ) > "${dir}/_run.log" 2>&1
}

log_of() { cat "$1/_run.log" 2>/dev/null; }

# ------------------------------------------------- argument-parsing probes ----
# These run a script far enough to see how it parsed its flags and no further, so they
# need no LaTeX toolchain. probe() records the exit status and the combined output;
# expect_probe() compares them against what the case should produce and collects every
# mismatch, so one test can report all of its sub-cases at once.

PROBE_OUT=""
PROBE_RC=0
PROBE_PROBLEMS=""

probe() {
    local dir="$1"; shift
    PROBE_OUT="$( cd "${dir}" && "$@" 2>&1 )"
    PROBE_RC=$?
}

# expect_probe LABEL zero|nonzero|any MUST_CONTAIN MUST_NOT_CONTAIN
# Either of the two strings may be empty, meaning "do not check this".
expect_probe() {
    local label="$1" want_rc="$2" needle="$3" forbidden="$4"
    case "${want_rc}" in
        zero)    (( PROBE_RC == 0 )) || PROBE_PROBLEMS+="[${label}: expected exit 0, got ${PROBE_RC}] " ;;
        nonzero) (( PROBE_RC != 0 )) || PROBE_PROBLEMS+="[${label}: expected a non-zero exit, got 0] " ;;
    esac
    if [[ -n "${needle}" ]] && ! grep -qF -- "${needle}" <<< "${PROBE_OUT}"; then
        PROBE_PROBLEMS+="[${label}: output never mentions '${needle}'] "
    fi
    if [[ -n "${forbidden}" ]] && grep -qF -- "${forbidden}" <<< "${PROBE_OUT}"; then
        PROBE_PROBLEMS+="[${label}: output still mentions '${forbidden}'] "
    fi
}

# Derive a fake published release asset from a freshly built expanded source, with a
# small edit so latexdiff has a real change to report.
make_release_asset() {
    local dir="$1" tag="$2" asset="$3" src="$4"
    mkdir -p "${dir}/_releases/${tag}"
    sed -e 's/Fixture Author/Earlier Fixture Author/' \
        -e 's/dominant cost/leading cost/' \
        -e 's/Further Reading/Earlier Further Reading/' \
        "${src}" > "${dir}/_releases/${tag}/${asset}"
    grep -q 'Earlier Fixture Author' "${dir}/_releases/${tag}/${asset}"
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

# ==================================================================== tests ====

LATEX_MISSING="$(missing_tools pdflatex bibtex latexpand)"
DIFF_MISSING="$(missing_tools pdflatex bibtex latexpand latexdiff jq)"

test_01_build_main() {
    local name="T01 build.sh builds the main document into dist/"
    if [[ -n "${LATEX_MISSING}" ]]; then skip "${name}" "${LATEX_MISSING}"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/build.sh" --root . --filename main --output-name main; then
        fail "${name}" "build.sh exited non-zero: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    local f
    for f in dist/main.pdf dist/main.bbl dist/main_expanded.tex; do
        [[ -s "${d}/${f}" ]] || { fail "${name}" "${f} is missing or empty"; return; }
    done
    pass "${name}"
}

test_02_appendix_does_not_clobber_main_bib() {
    local name="T02 building the appendix leaves dist/main.bib untouched"
    if [[ -n "${LATEX_MISSING}" ]]; then skip "${name}" "${LATEX_MISSING}"; return; fi
    if ! have ures-bib; then skip "${name}" "ures-bib"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/build.sh" --root . --filename main --output-name main; then
        fail "${name}" "the main build failed: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    [[ -s "${d}/dist/main.bib" ]] || { fail "${name}" "dist/main.bib was not produced"; return; }
    local before; before="$(sha "${d}/dist/main.bib")"

    if ! run_in "${d}" bash "${SCRIPTS}/build.sh" --root . --filename appendix --output-name appendix; then
        fail "${name}" "the appendix build failed: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    local f
    for f in dist/appendix.pdf dist/appendix.bbl dist/appendix.bib dist/appendix_expanded.tex; do
        [[ -s "${d}/${f}" ]] || { fail "${name}" "${f} is missing or empty"; return; }
    done

    local after; after="$(sha "${d}/dist/main.bib")"
    if [[ "${before}" != "${after}" ]]; then
        fail "${name}" "dist/main.bib changed while building the appendix (${before} -> ${after})"
        return
    fi
    # The two bibliographies are filtered from the same source, so they must differ.
    if [[ "$(sha "${d}/dist/appendix.bib")" == "${after}" ]]; then
        fail "${name}" "dist/appendix.bib is identical to dist/main.bib; the filter did not run per document"
        return
    fi
    pass "${name}"
}

test_03_prepare_release_without_appendix() {
    local name="T03 prepare-release.sh without --appendix leaves no appendix artifacts"
    if [[ -n "${LATEX_MISSING}" ]]; then skip "${name}" "${LATEX_MISSING}"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/prepare-release.sh" --root .; then
        fail "${name}" "prepare-release.sh exited non-zero: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    [[ -s "${d}/dist/main.pdf" ]] || { fail "${name}" "dist/main.pdf was not produced"; return; }
    local stray; stray="$(find "${d}/dist" -maxdepth 1 -name 'appendix*' -printf '%f ' 2>/dev/null)"
    if [[ -n "${stray}" ]]; then
        fail "${name}" "dist/ contains appendix artifacts: ${stray}"
        return
    fi
    pass "${name}"
}

test_04_prepare_release_missing_appendix() {
    local name="T04 prepare-release.sh fails on an --appendix that does not exist"
    new_workdir; local d="${WORKDIR}"
    if run_in "${d}" bash "${SCRIPTS}/prepare-release.sh" --root . --appendix nope; then
        fail "${name}" "expected a non-zero exit, got 0"
        return
    fi
    if ! log_of "${d}" | grep -q 'nope.tex'; then
        fail "${name}" "the error does not name the missing file: $(log_of "${d}" | tail -2 | tr '\n' ' ')"
        return
    fi
    pass "${name}"
}

test_05_trailing_bare_last() {
    local name="T05 prepare-release.sh survives a trailing bare --last (first release)"
    if [[ -n "${LATEX_MISSING}" ]]; then skip "${name}" "${LATEX_MISSING}"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/prepare-release.sh" --root . --last; then
        fail "${name}" "a bare --last aborted the run: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    [[ -s "${d}/dist/main.pdf" ]] || { fail "${name}" "dist/main.pdf was not produced"; return; }
    if [[ -e "${d}/dist/diff.pdf" ]]; then
        fail "${name}" "a diff was produced although there is no previous release"
        return
    fi
    pass "${name}"
}

test_06_explicit_bib_matches_autodetect() {
    local name="T06 --bib refs produces the same dist bibliography as auto-detection"
    if [[ -n "${LATEX_MISSING}" ]]; then skip "${name}" "${LATEX_MISSING}"; return; fi
    if ! have ures-bib; then skip "${name}" "ures-bib"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/build.sh" --root . --filename main --output-name auto; then
        fail "${name}" "the auto-detected build failed: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    if ! run_in "${d}" bash "${SCRIPTS}/build.sh" --root . --filename main --output-name explicit --bib refs; then
        fail "${name}" "the --bib build failed: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    [[ -s "${d}/dist/auto.bib" && -s "${d}/dist/explicit.bib" ]] \
        || { fail "${name}" "one of the bibliographies was not produced"; return; }
    if ! cmp -s "${d}/dist/auto.bib" "${d}/dist/explicit.bib"; then
        fail "${name}" "dist/auto.bib and dist/explicit.bib differ"
        return
    fi
    pass "${name}"
}

test_07_appendix_without_bibliography() {
    local name="T07 an appendix with no bibliography does not abort the release"
    if [[ -n "${LATEX_MISSING}" ]]; then skip "${name}" "${LATEX_MISSING}"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/prepare-release.sh" --root . --appendix appendix-nobib; then
        fail "${name}" "prepare-release.sh exited non-zero: $(log_of "${d}" | tail -5 | tr '\n' ' ')"
        return
    fi
    [[ -s "${d}/dist/appendix.pdf" ]] || { fail "${name}" "dist/appendix.pdf was not produced"; return; }
    [[ -s "${d}/dist/appendix_expanded.tex" ]] \
        || { fail "${name}" "dist/appendix_expanded.tex was not produced"; return; }
    pass "${name}"
}

test_08_next_flag_removed() {
    local name="T08 prepare-release.sh rejects the removed --next flag with an actionable message"
    new_workdir; local d="${WORKDIR}"
    if run_in "${d}" bash "${SCRIPTS}/prepare-release.sh" --root . --next 1.0.0; then
        fail "${name}" "expected a non-zero exit, got 0"
        return
    fi
    if ! log_of "${d}" | grep -q '\.releaserc'; then
        fail "${name}" "the message does not mention .releaserc: $(log_of "${d}" | tail -2 | tr '\n' ' ')"
        return
    fi
    pass "${name}"
}

# Build the current documents, then turn their expanded sources into a fake previous
# release. Echoes nothing; returns non-zero when the preparation itself failed.
seed_previous_release() {
    local d="$1" with_appendix="$2"
    run_in "${d}" bash "${SCRIPTS}/prepare-release.sh" --root . --appendix appendix || return 1
    make_release_asset "${d}" "v1.0.0" "source-1.0.0.tex" "${d}/dist/main_expanded.tex" || return 1
    if [[ "${with_appendix}" == "yes" ]]; then
        make_release_asset "${d}" "v1.0.0" "appendix-source-1.0.0.tex" \
            "${d}/dist/appendix_expanded.tex" || return 1
    fi
    rm -rf "${d}/dist" "${d}/build"
    return 0
}

test_09_release_without_previous_appendix() {
    local name="T09 a previous release without an appendix source warns and skips that diff"
    if [[ -n "${DIFF_MISSING}" ]]; then skip "${name}" "${DIFF_MISSING}"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! seed_previous_release "${d}" "no"; then
        fail "${name}" "could not seed the previous release: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    if ! run_in_stubbed "${d}" bash "${SCRIPTS}/prepare-release.sh" \
            --root . --last 1.0.0 --appendix appendix; then
        fail "${name}" "prepare-release.sh exited non-zero: $(log_of "${d}" | tail -5 | tr '\n' ' ')"
        return
    fi
    [[ -s "${d}/dist/diff.pdf" ]] || { fail "${name}" "dist/diff.pdf was not produced"; return; }
    if [[ -e "${d}/dist/appendix-diff.pdf" ]]; then
        fail "${name}" "an appendix diff was produced although the previous release has no appendix source"
        return
    fi
    if ! log_of "${d}" | grep -q 'appendix-source-1.0.0.tex is not attached'; then
        fail "${name}" "the missing appendix source was not reported as a warning"
        return
    fi
    pass "${name}"
}

test_09b_release_with_previous_appendix() {
    local name="T09b a previous release with an appendix source produces both diffs"
    if [[ -n "${DIFF_MISSING}" ]]; then skip "${name}" "${DIFF_MISSING}"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! seed_previous_release "${d}" "yes"; then
        fail "${name}" "could not seed the previous release: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    if ! run_in_stubbed "${d}" bash "${SCRIPTS}/prepare-release.sh" \
            --root . --last 1.0.0 --appendix appendix; then
        fail "${name}" "prepare-release.sh exited non-zero: $(log_of "${d}" | tail -5 | tr '\n' ' ')"
        return
    fi
    local f
    for f in dist/diff.pdf dist/appendix-diff.pdf; do
        [[ -s "${d}/${f}" ]] || { fail "${name}" "${f} is missing or empty"; return; }
    done
    pass "${name}"
}

test_10_diff_two_releases() {
    local name="T10 diff-releases.sh diffs two published releases"
    if [[ -n "${DIFF_MISSING}" ]]; then skip "${name}" "${DIFF_MISSING}"; return; fi

    # Seeded from the main document on purpose. main.tex loads the project's own
    # fixture.sty, which latexpand does not inline, so the published source only
    # compiles in the diff sandbox if diff-releases.sh carried the project's package
    # and asset files across. Diffing the appendix instead would not notice that.
    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/build.sh" --root . --filename main --output-name main; then
        fail "${name}" "the seed build failed: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    make_release_asset "${d}" "v1.0.0" "source-1.0.0.tex" "${d}/dist/main_expanded.tex" \
        || { fail "${name}" "could not build the v1.0.0 asset"; return; }
    mkdir -p "${d}/_releases/v1.1.0"
    cp "${d}/dist/main_expanded.tex" "${d}/_releases/v1.1.0/source-1.1.0.tex"
    rm -rf "${d}/dist" "${d}/build"

    if ! run_in_stubbed "${d}" bash "${SCRIPTS}/diff-releases.sh" \
            --root . --owner "${FAKE_OWNER}" --repo "${FAKE_REPO}" --old v1.0.0 --new v1.1.0; then
        fail "${name}" "diff-releases.sh exited non-zero: $(log_of "${d}" | tail -5 | tr '\n' ' ')"
        return
    fi
    [[ -s "${d}/dist/diff-v1.0.0-to-v1.1.0.pdf" ]] \
        || { fail "${name}" "dist/diff-v1.0.0-to-v1.1.0.pdf was not produced"; return; }

    # The PDF alone would not say why it compiled, so name the resources directly.
    local sandbox="${d}/build/diff-v1.0.0-to-v1.1.0"
    [[ -f "${sandbox}/fixture.sty" ]] \
        || { fail "${name}" "fixture.sty was not copied into the diff sandbox"; return; }
    [[ -d "${sandbox}/assets" ]] \
        || { fail "${name}" "assets/ was not copied into the diff sandbox"; return; }
    [[ -f "${sandbox}/fixturestyle.bst" ]] \
        || { fail "${name}" "fixturestyle.bst was not copied into the diff sandbox"; return; }
    pass "${name}"
}

test_11_dist_holds_only_publishable_artifacts() {
    local name="T11 after a full release dist/ holds publishable artifacts only"
    if [[ -n "${DIFF_MISSING}" ]]; then skip "${name}" "${DIFF_MISSING}"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! seed_previous_release "${d}" "yes"; then
        fail "${name}" "could not seed the previous release: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    if ! run_in_stubbed "${d}" bash "${SCRIPTS}/prepare-release.sh" \
            --root . --last 1.0.0 --appendix appendix; then
        fail "${name}" "prepare-release.sh exited non-zero: $(log_of "${d}" | tail -5 | tr '\n' ' ')"
        return
    fi

    local junk=""
    local pattern
    for pattern in '*.log' '*.aux' '*.out' '*.blg' '*.cls' '*.sty' '*.bst' 'source-*.tex'; do
        local hits
        hits="$(find "${d}/dist" -maxdepth 1 -name "${pattern}" -printf '%f ' 2>/dev/null)"
        [[ -n "${hits}" ]] && junk="${junk}${hits}"
    done
    [[ -d "${d}/dist/assets" ]] && junk="${junk}assets/ "

    if [[ -n "${junk}" ]]; then
        fail "${name}" "dist/ contains non-publishable entries: ${junk}"
        return
    fi
    # Guard against the check passing because nothing was produced at all.
    local f
    for f in dist/main.pdf dist/appendix.pdf dist/diff.pdf dist/appendix-diff.pdf; do
        [[ -s "${d}/${f}" ]] || { fail "${name}" "${f} is missing, so the check proved nothing"; return; }
    done
    pass "${name}"
}

test_12_syntax_and_help() {
    local name="T12 every scripts/latex/*.sh parses, and --help exits 0 where it exists"
    local script base bad=""
    for script in "${SCRIPTS}"/*.sh; do
        base="$(basename "${script}")"
        bash -n "${script}" 2>/dev/null || bad="${bad}${bad:+, }${base} (syntax)"
    done
    for script in "${SCRIPTS}"/*.sh; do
        base="$(basename "${script}")"
        grep -qE '^[[:space:]]*--help\)' "${script}" || continue
        if ! bash "${script}" --help > /dev/null 2>&1; then
            bad="${bad}${bad:+, }${base} (--help)"
        fi
    done
    if [[ -n "${bad}" ]]; then
        fail "${name}" "${bad}"
        return
    fi
    pass "${name}"
}

test_13_validate() {
    local name="T13 validate.sh accepts the fixture and rejects a missing main file"
    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/validate.sh" --root .; then
        fail "${name}" "validate.sh rejected a valid project: $(log_of "${d}" | tail -2 | tr '\n' ' ')"
        return
    fi
    if run_in "${d}" bash "${SCRIPTS}/validate.sh" --root . --filename nope; then
        fail "${name}" "validate.sh accepted a missing main file"
        return
    fi
    pass "${name}"
}

test_14_flags_do_not_swallow_the_next_flag() {
    local name="T14 a value-less flag no longer swallows the flag that follows it"
    # Pure argument parsing: every case below stops before any document is compiled,
    # so this test runs even with no LaTeX toolchain installed.
    new_workdir; local d="${WORKDIR}"
    PROBE_PROBLEMS=""

    # The case that matters. With the old parser --last ate "--main" and the script
    # then died on "unknown arg: nope"; worse, a trailing "--last --main" left
    # LAST_VERSION="--main" and the release tried to download source---main.tex.
    # Now --last must take no value and --main must still be seen.
    probe "${d}" env -u GITHUB_REPOSITORY_OWNER -u GITHUB_REPOSITORY \
        bash "${SCRIPTS}/prepare-release.sh" --root . --last --main nope
    expect_probe "--last --main nope" nonzero "nope.tex not found" "unknown arg"
    # Same output: an empty --last must not look like a previous release.
    expect_probe "--last --main nope (no phantom version)" any "" "GITHUB_REPOSITORY_OWNER"

    # The flag after a value-less --last is honoured whichever flag it is.
    probe "${d}" env -u GITHUB_REPOSITORY_OWNER -u GITHUB_REPOSITORY \
        bash "${SCRIPTS}/prepare-release.sh" --root . --last --appendix nope
    expect_probe "--last --appendix nope" nonzero "--appendix was given but nope.tex" "unknown arg"

    # A real version still parses as a real version: with no repository in the
    # environment the diffs cannot run, and the script has to say so.
    probe "${d}" env -u GITHUB_REPOSITORY_OWNER -u GITHUB_REPOSITORY \
        bash "${SCRIPTS}/prepare-release.sh" --root . --last 1.0.0 --main nope
    expect_probe "--last 1.0.0 (version kept)" nonzero "GITHUB_REPOSITORY_OWNER" ""

    # ...and the flag after it is still read as its own flag.
    probe "${d}" env GITHUB_REPOSITORY_OWNER="${FAKE_OWNER}" \
                     GITHUB_REPOSITORY="${FAKE_OWNER}/${FAKE_REPO}" \
        bash "${SCRIPTS}/prepare-release.sh" --root . --last 1.0.0 --main nope
    expect_probe "--last 1.0.0 --main nope" nonzero "nope.tex not found" "unknown arg"

    # The same parser is shared, so check a second script: a value-less --filename
    # must report itself as empty rather than consume --output-name.
    probe "${d}" bash "${SCRIPTS}/build.sh" --root . --filename --output-name main
    expect_probe "build.sh --filename --output-name" nonzero "--filename cannot be empty" "unknown arg"

    # And a third: --help after a value-less flag must still print the help.
    probe "${d}" bash "${SCRIPTS}/validate.sh" --root . --filename --help
    expect_probe "validate.sh --filename --help" zero "Usage: validate.sh" "--help.tex"

    if [[ -n "${PROBE_PROBLEMS}" ]]; then
        fail "${name}" "${PROBE_PROBLEMS}"
        return
    fi
    pass "${name}"
}

test_15_custom_bst_reaches_the_sandbox() {
    local name="T15 a custom .bst in the project root reaches the build sandbox"
    if [[ -n "${LATEX_MISSING}" ]]; then skip "${name}" "${LATEX_MISSING}"; return; fi

    new_workdir; local d="${WORKDIR}"
    if ! run_in "${d}" bash "${SCRIPTS}/build.sh" --root . --filename styled --output-name styled; then
        fail "${name}" "build.sh exited non-zero: $(log_of "${d}" | tail -3 | tr '\n' ' ')"
        return
    fi
    [[ -f "${d}/build/styled/fixturestyle.bst" ]] \
        || { fail "${name}" "fixturestyle.bst was not copied into build/styled/"; return; }

    # Exit status alone would prove nothing here: compile_document swallows bibtex
    # failures, so a style bibtex cannot find still leaves a green build and a
    # zero-byte dist/<name>.bbl. Check that the style actually ran instead.
    [[ -s "${d}/dist/styled.bbl" ]] \
        || { fail "${name}" "dist/styled.bbl is empty; bibtex never resolved the style"; return; }
    if ! grep -q 'fixturestyle' "${d}/dist/styled.bbl"; then
        fail "${name}" "dist/styled.bbl carries no marker from the project's own style file"
        return
    fi
    if ! grep -q '\\bibitem' "${d}/dist/styled.bbl"; then
        fail "${name}" "dist/styled.bbl contains no \\bibitem entries"
        return
    fi
    # latexpand inlines the .bbl, so the published source must carry it too.
    if ! grep -q 'fixturestyle' "${d}/dist/styled_expanded.tex"; then
        fail "${name}" "dist/styled_expanded.tex does not carry the inlined bibliography"
        return
    fi
    pass "${name}"
}

# ===================================================================== main ====

main() {
    [[ -d "${SCRIPTS}" ]] || { echo "scripts/latex not found at ${SCRIPTS}" >&2; exit 2; }
    [[ -d "${FIXTURE}" ]] || { echo "fixtures not found at ${FIXTURE}" >&2; exit 2; }

    echo "LaTeX release-script smoke tests"
    echo "  scripts:  ${SCRIPTS}"
    echo "  fixtures: ${FIXTURE}"
    printf '  toolchain:'
    local t
    for t in pdflatex bibtex latexdiff latexpand ures-bib jq; do
        if have "${t}"; then printf ' %s=yes' "${t}"; else printf ' %s=no' "${t}"; fi
    done
    echo
    echo

    test_01_build_main
    test_02_appendix_does_not_clobber_main_bib
    test_03_prepare_release_without_appendix
    test_04_prepare_release_missing_appendix
    test_05_trailing_bare_last
    test_06_explicit_bib_matches_autodetect
    test_07_appendix_without_bibliography
    test_08_next_flag_removed
    test_09_release_without_previous_appendix
    test_09b_release_with_previous_appendix
    test_10_diff_two_releases
    test_11_dist_holds_only_publishable_artifacts
    test_12_syntax_and_help
    test_13_validate
    test_14_flags_do_not_swallow_the_next_flag
    test_15_custom_bst_reaches_the_sandbox

    echo
    echo "-----------------------------------------------------------"
    printf 'passed %d   failed %d   skipped %d\n' "${PASS_COUNT}" "${FAIL_COUNT}" "${SKIP_COUNT}"
    if (( FAIL_COUNT )); then
        printf 'failing tests:\n'
        printf '  %s\n' "${FAILED_TESTS[@]}"
        echo "re-run with KEEP_WORKDIRS=1 to inspect the temporary working copies"
        return 1
    fi
    echo "all runnable tests passed"
    return 0
}

main "$@"
