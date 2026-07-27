#!/bin/zsh

set -euo pipefail

# Generate (and EdDSA-sign) the Sparkle appcast.xml for a directory of release archives.
#
# Why this exists: build-app.sh injects the Sparkle feed URL / public key into the shipped
# app, and notarize-app.sh signs and staples the bundle, but nothing produced the *appcast*
# that clients actually poll. Without a signed appcast the update channel is wired but dead:
# the client fetches the feed URL and finds nothing to install. This wraps Sparkle's own
# `generate_appcast` tool (resolved from the SPM artifact bundle) so releasing an update is a
# single, repeatable command instead of hand-locating a binary under .build/.
#
# The private EdDSA signing key is NEVER passed on the command line by default; `generate_appcast`
# reads it from the macOS Keychain (created once via `generate_keys`). Use --ed-key-file only for
# CI machines that cannot reach the Keychain, and keep that file out of the repo.

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
PACKAGE_ROOT="$REPO_ROOT"

ARCHIVES_DIR=""
DOWNLOAD_URL_PREFIX=""
OUTPUT_PATH=""
KEYCHAIN_ACCOUNT=""
ED_KEY_FILE=""
CHANNEL=""
RELEASE_TAG=""
FEED_FILE="${REPO_ROOT}/release/appcast.xml"
ALLOW_MULTIPLE_ARCHIVES=0

usage() {
    cat <<'EOF'
Usage: scripts/generate-appcast.sh --archives-dir <dir> --tag <tag> [options]

Generate and EdDSA-sign the Sparkle appcast for one new release, merging it into the
published feed at release/appcast.xml.

The archives directory is a STAGING directory that must hold exactly one notarized/stapled
release .zip (plus, optionally, a matching .html/.md/.txt release-note file with the same
base name). The script seeds it with the currently published feed, runs Sparkle's
generate_appcast, and writes the merged result back to the feed file.

Options:
  --archives-dir <dir>        Staging directory holding the new release archive. Required.
  --tag <tag>                 Git tag of the GitHub Release the archive is attached to, e.g.
                              v1.1.2. Used to derive the download URL prefix from the origin
                              remote. Required unless --download-url-prefix is given.
  --feed-file <path>          Published feed to merge into and write back
                              (default: release/appcast.xml). Pass "none" to skip merging
                              and leave appcast.xml in the staging directory only.
  --download-url-prefix <url> Override the URL prefix derived from --tag.
  --output <path>             Output appcast path (default: <archives-dir>/appcast.xml).
  --keychain-account <name>   Keychain account holding the private EdDSA key (default: ed25519).
  --ed-key-file <path>        Read the private EdDSA key from a file instead of the Keychain.
                              Use only where the Keychain is unavailable (e.g. CI); never commit it.
  --channel <name>            Sparkle channel name for the generated entries (optional).
  --allow-multiple-archives   Escape hatch for rebuilding a feed from scratch. Read the
                              warning in the single-archive guard below before using it.
  --help                      Show this help message.
EOF
}

log_info() {
    printf '[generate-appcast] %s\n' "$1"
}

fail() {
    printf '[generate-appcast][error] %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archives-dir)
            ARCHIVES_DIR="$2"
            shift 2
            ;;
        --download-url-prefix)
            DOWNLOAD_URL_PREFIX="$2"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --keychain-account)
            KEYCHAIN_ACCOUNT="$2"
            shift 2
            ;;
        --ed-key-file)
            ED_KEY_FILE="$2"
            shift 2
            ;;
        --channel)
            CHANNEL="$2"
            shift 2
            ;;
        --tag)
            RELEASE_TAG="$2"
            shift 2
            ;;
        --feed-file)
            FEED_FILE="$2"
            shift 2
            ;;
        --allow-multiple-archives)
            ALLOW_MULTIPLE_ARCHIVES=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "Unknown option: $1"
            ;;
    esac
done

[[ -n "$ARCHIVES_DIR" ]] || { usage >&2; fail "--archives-dir is required."; }
[[ -d "$ARCHIVES_DIR" ]] || fail "Archives directory not found: $ARCHIVES_DIR"

archive_count=0
while IFS= read -r _; do
    archive_count=$((archive_count + 1))
done < <(find "$ARCHIVES_DIR" -maxdepth 1 \( -name '*.zip' -o -name '*.dmg' \) -print 2>/dev/null)

if [[ $archive_count -eq 0 ]]; then
    fail "No .zip/.dmg release archives found in $ARCHIVES_DIR; run scripts/build-app.sh (and notarize-app.sh) first."
fi

# Single-archive guard.
#
# generate_appcast rewrites the enclosure URL of EVERY archive it finds in the staging
# directory using the CURRENT --download-url-prefix. Our archives live under per-tag GitHub
# Release URLs, so if a previous release's zip is still sitting in the staging directory, its
# already-published entry gets silently rewritten to the NEW tag's URL — a 404 that turns the
# whole update channel dead for users on that version. Verified behaviour: with both zips
# present the tool reports "updated 1 existing update" and rewrites the old URL; with only the
# new zip present it reports "updated 0 existing updates" and leaves the old entry intact.
#
# Entries for archives that are absent are copied through untouched, which is exactly what we
# want — so stage one archive per release and let the feed file carry the history.
if [[ $archive_count -gt 1 && $ALLOW_MULTIPLE_ARCHIVES -eq 0 ]]; then
    fail "Staging directory holds $archive_count archives. Stage exactly one release archive: generate_appcast would rewrite every staged archive's download URL to the current --tag, breaking the already-published entries. Pass --allow-multiple-archives only when deliberately rebuilding the whole feed under one URL prefix."
fi

if [[ -n "$ED_KEY_FILE" ]]; then
    [[ -f "$ED_KEY_FILE" ]] || fail "EdDSA key file not found: $ED_KEY_FILE"
fi

# Derive the download URL prefix from the release tag and the origin remote so a release never
# ships an appcast pointing at the wrong tag because someone hand-typed the prefix.
if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
    [[ -n "$RELEASE_TAG" ]] || { usage >&2; fail "--tag is required (or pass --download-url-prefix explicitly)."; }

    origin_url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
    [[ -n "$origin_url" ]] || fail "Cannot derive the download URL: no 'origin' remote. Pass --download-url-prefix explicitly."

    # Accept both git@github.com:owner/repo.git and https://github.com/owner/repo(.git)
    repo_slug="${origin_url##*github.com[:/]}"
    repo_slug="${repo_slug%.git}"
    [[ "$repo_slug" == */* ]] || fail "Cannot parse owner/repo from origin remote: $origin_url"

    DOWNLOAD_URL_PREFIX="https://github.com/${repo_slug}/releases/download/${RELEASE_TAG}/"
    log_info "Derived download URL prefix: $DOWNLOAD_URL_PREFIX"
fi

# Seed the staging directory with the currently published feed so generate_appcast merges the
# new item into the existing history instead of emitting a feed with a single item.
if [[ "$FEED_FILE" != "none" ]]; then
    if [[ -f "$FEED_FILE" ]]; then
        if [[ -f "${ARCHIVES_DIR}/appcast.xml" ]]; then
            log_info "Staging directory already has an appcast.xml; leaving it in place."
        else
            log_info "Seeding staging directory from published feed: $FEED_FILE"
            cp "$FEED_FILE" "${ARCHIVES_DIR}/appcast.xml"
        fi
    else
        log_info "No published feed at $FEED_FILE yet; generating a fresh one."
    fi
fi

# Locate Sparkle's generate_appcast from the resolved SPM artifact bundle. The exact path under
# .build/ is version-dependent, so search rather than hard-code it. Fall back to the checkout copy.
locate_generate_appcast() {
    local candidate
    for candidate in \
        "$PACKAGE_ROOT"/.build/artifacts/**/Sparkle/bin/generate_appcast \
        "$PACKAGE_ROOT"/.build/checkouts/Sparkle/bin/generate_appcast \
        "$PACKAGE_ROOT"/.build/checkouts/Sparkle/generate_appcast; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

setopt local_options extended_glob null_glob
GENERATE_APPCAST="$(locate_generate_appcast || true)"

if [[ -z "$GENERATE_APPCAST" ]]; then
    log_info "generate_appcast not found in build artifacts; resolving the Sparkle package first"
    swift build --package-path "$PACKAGE_ROOT" >/dev/null 2>&1 || true
    GENERATE_APPCAST="$(locate_generate_appcast || true)"
fi

[[ -n "$GENERATE_APPCAST" ]] || fail "Could not locate Sparkle's generate_appcast tool under .build/. Run 'swift build' and retry."
log_info "Using generate_appcast: $GENERATE_APPCAST"

args=()
[[ -n "$DOWNLOAD_URL_PREFIX" ]] && args+=(--download-url-prefix "$DOWNLOAD_URL_PREFIX")
[[ -n "$OUTPUT_PATH" ]] && args+=(-o "$OUTPUT_PATH")
[[ -n "$KEYCHAIN_ACCOUNT" ]] && args+=(--account "$KEYCHAIN_ACCOUNT")
[[ -n "$ED_KEY_FILE" ]] && args+=(--ed-key-file "$ED_KEY_FILE")
[[ -n "$CHANNEL" ]] && args+=(--channel "$CHANNEL")

log_info "Generating signed appcast for archives in $ARCHIVES_DIR"
"$GENERATE_APPCAST" "${args[@]}" "$ARCHIVES_DIR"

RESULT_APPCAST="${OUTPUT_PATH:-$ARCHIVES_DIR/appcast.xml}"
[[ -f "$RESULT_APPCAST" ]] || fail "generate_appcast did not produce an appcast at $RESULT_APPCAST"

# Sparkle silently fails every update check on a feed it cannot parse, so never write malformed
# XML back to the published feed. generate_appcast itself refuses to parse a malformed seed, but
# check the output too so a bad merge can never reach Pages.
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$RESULT_APPCAST" || fail "Generated appcast is not well-formed XML: $RESULT_APPCAST"
elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, xml.parsers.expat; xml.parsers.expat.ParserCreate().ParseFile(open(sys.argv[1], "rb"))' "$RESULT_APPCAST" \
        || fail "Generated appcast is not well-formed XML: $RESULT_APPCAST"
else
    log_warn "Neither xmllint nor python3 is available; skipped the XML well-formedness check."
fi

# An unsigned feed is worse than no feed: clients with SUPublicEDKey set reject every item, so
# the update channel looks alive but can never install anything. generate_appcast only warns
# when the key is missing, so turn that into a hard failure here.
if ! grep -q 'sparkle:edSignature=' "$RESULT_APPCAST"; then
    fail "Generated appcast has no sparkle:edSignature. The private EdDSA key was not available (run 'generate_keys' once, or pass --ed-key-file). Do NOT publish this file: clients would reject every item."
fi

if [[ "$FEED_FILE" != "none" ]]; then
    mkdir -p "${FEED_FILE:h}"
    cp "$RESULT_APPCAST" "$FEED_FILE"
    log_info "Published feed updated: $FEED_FILE"
    log_info "Commit and push it — .github/workflows/publish-appcast.yml deploys it to GitHub Pages."
else
    log_info "Appcast written: $RESULT_APPCAST"
    log_info "Publish this appcast.xml to your Sparkle feed URL host."
fi
