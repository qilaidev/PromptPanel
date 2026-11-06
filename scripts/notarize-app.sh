#!/bin/zsh

set -euo pipefail

APP_PATH=""
ARCHIVE_PATH=""
KEYCHAIN_PROFILE=""
SKIP_STAPLE=0
SKIP_ASSESS=0
ARCHIVE_KIND=""
ARCHIVE_WAS_GENERATED=0

usage() {
    cat <<'EOF'
Usage: scripts/notarize-app.sh [options]

Submit a signed PromptPanel build to Apple notarization, then staple and assess it.

Options:
  --app-path <path>           Path to the signed .app bundle. Required.
  --archive-path <path>       Path to the signed zip/dmg/pkg to submit. Optional.
                              If omitted, the script creates a temporary zip from --app-path.
                              Zip archives are rebuilt after stapling; dmg/pkg archives are stapled directly.
  --keychain-profile <name>   notarytool keychain profile name. Required.
  --skip-staple               Skip stapler staple/validate.
  --skip-assess               Skip Gatekeeper assessment after notarization.
  --help                      Show this help message.
EOF
}

log_info() {
    printf '[notarize-app] %s\n' "$1"
}

fail() {
    printf '[notarize-app][error] %s\n' "$1" >&2
    exit 1
}

archive_kind() {
    local archive_path="$1"

    case "${archive_path:l}" in
        *.zip)
            printf 'zip\n'
            ;;
        *.dmg)
            printf 'dmg\n'
            ;;
        *.pkg)
            printf 'pkg\n'
            ;;
        *)
            printf 'unknown\n'
            ;;
    esac
}

create_zip_archive() {
    local app_path="$1"
    local archive_path="$2"

    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
}

staple_and_validate() {
    local target_path="$1"

    xcrun stapler staple "$target_path"
    xcrun stapler validate "$target_path"
}

assess_path() {
    local target_path="$1"
    local target_kind="$2"

    case "$target_kind" in
        app)
            spctl --assess --type execute --verbose=4 "$target_path"
            ;;
        dmg)
            spctl --assess --type open --verbose=4 "$target_path"
            ;;
        pkg)
            spctl --assess --type install --verbose=4 "$target_path"
            ;;
        *)
            fail "Unsupported assessment target kind: $target_kind"
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)
            APP_PATH="$2"
            shift 2
            ;;
        --archive-path)
            ARCHIVE_PATH="$2"
            shift 2
            ;;
        --keychain-profile)
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --skip-staple)
            SKIP_STAPLE=1
            shift
            ;;
        --skip-assess)
            SKIP_ASSESS=1
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

[[ -n "$APP_PATH" ]] || fail "--app-path is required."
[[ -n "$KEYCHAIN_PROFILE" ]] || fail "--keychain-profile is required."
[[ -d "$APP_PATH" ]] || fail "App bundle not found: $APP_PATH"

command -v xcrun >/dev/null 2>&1 || fail "xcrun is unavailable."
xcrun --find notarytool >/dev/null 2>&1 || fail "notarytool is unavailable on this machine."

TEMP_DIR=""
cleanup() {
    [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ -z "$ARCHIVE_PATH" ]]; then
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/promptpanel-notary.XXXXXX")"
    ARCHIVE_PATH="${TEMP_DIR}/$(basename "${APP_PATH:r}").zip"
    ARCHIVE_WAS_GENERATED=1
    log_info "Creating temporary archive for notarization submit"
    create_zip_archive "$APP_PATH" "$ARCHIVE_PATH"
fi

[[ -f "$ARCHIVE_PATH" ]] || fail "Archive not found: $ARCHIVE_PATH"

ARCHIVE_KIND="$(archive_kind "$ARCHIVE_PATH")"
[[ "$ARCHIVE_KIND" != "unknown" ]] || fail "Unsupported archive type for notarization: $ARCHIVE_PATH"

log_info "Submitting archive to Apple notarization"
xcrun notarytool submit "$ARCHIVE_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait

if [[ $SKIP_STAPLE -eq 0 ]]; then
    xcrun --find stapler >/dev/null 2>&1 || fail "stapler is unavailable on this machine."
    log_info "Stapling notarization ticket to app bundle"
    staple_and_validate "$APP_PATH"

    case "$ARCHIVE_KIND" in
        zip)
            if [[ $ARCHIVE_WAS_GENERATED -eq 0 ]]; then
                log_info "Rebuilding zip archive so the shipped artifact contains the stapled app bundle"
                rm -f "$ARCHIVE_PATH"
                create_zip_archive "$APP_PATH" "$ARCHIVE_PATH"
            fi
            ;;
        dmg|pkg)
            log_info "Stapling notarization ticket to distributable archive"
            staple_and_validate "$ARCHIVE_PATH"
            ;;
    esac
fi

if [[ $SKIP_ASSESS -eq 0 ]]; then
    command -v spctl >/dev/null 2>&1 || fail "spctl is unavailable on this machine."
    case "$ARCHIVE_KIND" in
        dmg|pkg)
            log_info "Running Gatekeeper assessment for distributable archive"
            assess_path "$ARCHIVE_PATH" "$ARCHIVE_KIND"
            ;;
        *)
            log_info "Running Gatekeeper assessment for app bundle"
            assess_path "$APP_PATH" app
            ;;
    esac
fi

log_info "Notarization flow completed successfully"
