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

usage() {
    cat <<'EOF'
Usage: scripts/generate-appcast.sh --archives-dir <dir> [options]

Generate and EdDSA-sign a Sparkle appcast.xml for the release archives in a directory.
The archives directory should contain the notarized/stapled release .zip (and, optionally,
matching .html/.md/.txt release-note files with the same base name).

Options:
  --archives-dir <dir>        Directory holding the release .zip archives. Required.
                              appcast.xml is written into this directory (or --output).
  --download-url-prefix <url> URL prefix where the archives will be hosted, e.g.
                              https://downloads.example.com/promptpanel/ . Recommended so the
                              generated appcast points at the real download location.
  --output <path>             Output appcast path (default: <archives-dir>/appcast.xml).
  --keychain-account <name>   Keychain account holding the private EdDSA key (default: ed25519).
  --ed-key-file <path>        Read the private EdDSA key from a file instead of the Keychain.
                              Use only where the Keychain is unavailable (e.g. CI); never commit it.
  --channel <name>            Sparkle channel name for the generated entries (optional).
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

if [[ -z "$(find "$ARCHIVES_DIR" -maxdepth 1 \( -name '*.zip' -o -name '*.dmg' \) -print -quit 2>/dev/null)" ]]; then
    fail "No .zip/.dmg release archives found in $ARCHIVES_DIR; run scripts/build-app.sh (and notarize-app.sh) first."
fi

if [[ -n "$ED_KEY_FILE" ]]; then
    [[ -f "$ED_KEY_FILE" ]] || fail "EdDSA key file not found: $ED_KEY_FILE"
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

log_info "Appcast written: $RESULT_APPCAST"
log_info "Publish this appcast.xml and the referenced archives to your Sparkle feed URL host."
