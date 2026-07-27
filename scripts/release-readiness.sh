#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
PACKAGE_ROOT="$REPO_ROOT"
OUTPUT_ROOT="${REPO_ROOT}/dist/release-readiness"
SIGN_IDENTITY="none"
PUBLIC_DISTRIBUTION=0
ALLOW_BUILD_ONLY_TESTS=0
SKIP_SMOKE_LAUNCH=0
SHORT_VERSION_OVERRIDE=""
BUILD_VERSION_OVERRIDE=""
SPARKLE_FEED_URL=""
SPARKLE_PUBLIC_ED_KEY=""
SMOKE_TIMEOUT_SECONDS=12

# The canonical Sparkle feed, published from release/appcast.xml by
# .github/workflows/publish-appcast.yml. This value is baked into every shipped binary as
# SUFeedURL and cannot be changed for already-installed clients, so it is pinned here and
# asserted on every public build rather than retyped per release.
CANONICAL_SPARKLE_FEED_URL="https://tytsxai.github.io/PromptPanel/appcast.xml"

usage() {
    cat <<'EOF'
Usage: scripts/release-readiness.sh [options]

Runs the local release-readiness checks for PromptPanel:
  1. validate shell script syntax
  2. validate documentation structure, search metadata, and sync guardrails
  3. build the Swift package
  4. run swift test
  5. build a release .app and zip
  6. verify code signatures
  7. smoke-launch the built app with isolated data directories
  8. hand off the signed archive to notarization via scripts/notarize-app.sh when needed

Options:
  --output-dir <path>          Output directory for the release bundle.
  --sign-identity <id>         codesign identity passed to build-app.sh.
  --allow-build-only-tests     Allow build-only test validation when this machine lacks xctest.
  --public-distribution        Fail if the build still uses ad-hoc signing or this machine lacks xctest.
  --skip-smoke-launch          Skip the isolated startup smoke check.
  --short-version <ver>        Override CFBundleShortVersionString.
  --build-version <ver>        Override CFBundleVersion.
  --sparkle-feed-url <url>     Inject SUFeedURL into the packaged app.
  --sparkle-public-ed-key <k>  Inject SUPublicEDKey into the packaged app.
  --help                       Show this help message.
EOF
}

log_info() {
    printf '[release-readiness] %s\n' "$1"
}

log_warn() {
    printf '[release-readiness][warn] %s\n' "$1" >&2
}

fail() {
    printf '[release-readiness][error] %s\n' "$1" >&2
    exit 1
}

# Verify a packaged .app's code signature with NO exemptions.
#
# This used to tolerate "unsealed contents present in the bundle root", which is what the
# app-root resource-bundle symlinks produced. That tolerance was wrong for anything we ship:
# Gatekeeper runs the same validation on the user's machine, so an app that only passed here
# was blocked on first launch after download and rejected by Sparkle as an update. The
# symlinks are gone (see build-app.sh); if this diagnostic ever reappears, something put
# content back at the bundle root and the build is not distributable.
verify_bundle_signature() {
    local target="$1"
    local output
    if output="$(codesign --verify --deep --strict --verbose=2 "$target" 2>&1)"; then
        return 0
    fi
    printf '%s\n' "$output" >&2
    if grep -q 'unsealed contents present in the bundle root' <<<"$output"; then
        log_warn "The bundle root carries unsealed content. Gatekeeper will reject this build and Sparkle will refuse to install it; keep SwiftPM resource bundles under Contents/Resources only."
    fi
    return 1
}

activate_full_xcode_if_available() {
    local candidates=()
    local candidate

    if [[ -n "${DEVELOPER_DIR:-}" ]]; then
        candidates+=("${DEVELOPER_DIR:A}")
    fi

    candidates+=(
        "/Applications/Xcode.app/Contents/Developer"
        "/Applications/Xcode-beta.app/Contents/Developer"
    )

    for candidate in "${candidates[@]}"; do
        [[ -d "$candidate" ]] || continue
        if DEVELOPER_DIR="$candidate" xcrun --find xctest >/dev/null 2>&1; then
            export DEVELOPER_DIR="$candidate"
            log_info "Using full Xcode developer directory: $DEVELOPER_DIR"
            return 0
        fi
    done

    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --sign-identity)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --allow-build-only-tests)
            ALLOW_BUILD_ONLY_TESTS=1
            shift
            ;;
        --public-distribution)
            PUBLIC_DISTRIBUTION=1
            shift
            ;;
        --skip-smoke-launch)
            SKIP_SMOKE_LAUNCH=1
            shift
            ;;
        --short-version)
            SHORT_VERSION_OVERRIDE="$2"
            shift 2
            ;;
        --build-version)
            BUILD_VERSION_OVERRIDE="$2"
            shift 2
            ;;
        --sparkle-feed-url)
            SPARKLE_FEED_URL="$2"
            shift 2
            ;;
        --sparkle-public-ed-key)
            SPARKLE_PUBLIC_ED_KEY="$2"
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

if [[ ! -d "$PACKAGE_ROOT" ]]; then
    fail "Package root not found: $PACKAGE_ROOT"
fi

if [[ -n "$SPARKLE_FEED_URL" && -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    fail "Sparkle feed URL was provided, but SUPublicEDKey is missing."
fi

if [[ -z "$SPARKLE_FEED_URL" && -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    fail "Sparkle public key was provided, but SUFeedURL is missing."
fi

if [[ -n "$SPARKLE_FEED_URL" && "$SPARKLE_FEED_URL" != https://* ]]; then
    fail "Sparkle feed URL must use https:// to prevent update-metadata tampering (got: ${SPARKLE_FEED_URL})."
fi

if [[ $PUBLIC_DISTRIBUTION -eq 1 && "$SIGN_IDENTITY" == "none" ]]; then
    fail "Public distribution precheck requires a non-ad-hoc signing identity."
fi

# A public build that ships without SUFeedURL/SUPublicEDKey is unrecoverable: those values live
# in the installed app's Info.plist, so every user who installs that build is stranded on it
# forever and can only update by manually re-downloading. Default the feed to the canonical
# Pages URL so a release cannot silently omit it, and require the matching public key.
if [[ $PUBLIC_DISTRIBUTION -eq 1 ]]; then
    if [[ -z "$SPARKLE_FEED_URL" ]]; then
        SPARKLE_FEED_URL="$CANONICAL_SPARKLE_FEED_URL"
        log_info "Defaulting Sparkle feed URL to the canonical value: $SPARKLE_FEED_URL"
    elif [[ "$SPARKLE_FEED_URL" != "$CANONICAL_SPARKLE_FEED_URL" ]]; then
        log_warn "Sparkle feed URL differs from the canonical value ($CANONICAL_SPARKLE_FEED_URL). Already-installed clients poll the URL baked into their own build; only use a different feed deliberately."
    fi

    if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
        fail "Public distribution requires --sparkle-public-ed-key. Run Sparkle's generate_keys once (it stores the private key in your Keychain and prints the public key), then pass that public key here. Shipping without it strands every installer of this build with no update path."
    fi
fi

mkdir -p "$OUTPUT_ROOT"

log_info "Validating shell scripts"
zsh -n "${REPO_ROOT}/scripts/build-app.sh"
zsh -n "${REPO_ROOT}/scripts/launch-computer-use.sh"
zsh -n "${REPO_ROOT}/scripts/check-docs.sh"
zsh -n "${REPO_ROOT}/scripts/notarize-app.sh"
zsh -n "${REPO_ROOT}/scripts/generate-appcast.sh"
zsh -n "${REPO_ROOT}/scripts/restore-backup.sh"
zsh -n "${REPO_ROOT}/scripts/release-readiness.sh"

log_info "Validating documentation consistency"
"${REPO_ROOT}/scripts/check-docs.sh"

TEST_RUNNER_AVAILABLE=0
if xcrun --find xctest >/dev/null 2>&1; then
    TEST_RUNNER_AVAILABLE=1
elif activate_full_xcode_if_available; then
    TEST_RUNNER_AVAILABLE=1
else
    if [[ $ALLOW_BUILD_ONLY_TESTS -eq 1 ]]; then
        log_warn "xctest is unavailable on this machine; continuing in build-only test validation mode because --allow-build-only-tests was set."
    else
        fail "Real test execution requires xctest. Install/select a full Xcode toolchain, or rerun with --allow-build-only-tests to accept build-only validation."
    fi
fi

log_info "Building Swift package"
swift build --package-path "$PACKAGE_ROOT"

if [[ $TEST_RUNNER_AVAILABLE -eq 1 ]]; then
    log_info "Running swift test"
    swift test --package-path "$PACKAGE_ROOT"
else
    log_info "Running swift test in build-only validation mode"
    swift build --package-path "$PACKAGE_ROOT" --build-tests
fi

if [[ $PUBLIC_DISTRIBUTION -eq 1 && $TEST_RUNNER_AVAILABLE -eq 0 ]]; then
    fail "Public distribution precheck failed because xctest is unavailable on this machine."
fi

# Public distribution always needs a monotonically increasing CFBundleVersion so Sparkle (when
# enabled) and macOS update logic can distinguish releases. If the caller did not pass one,
# derive it from the current git history. This avoids the silent footgun where a forgotten
# --build-version ships a 1.0.x update that already-installed clients see as "same version".
if [[ $PUBLIC_DISTRIBUTION -eq 1 && -z "$BUILD_VERSION_OVERRIDE" ]]; then
    if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        BUILD_VERSION_OVERRIDE="$(git -C "$REPO_ROOT" rev-list --count HEAD)"
        [[ -n "$BUILD_VERSION_OVERRIDE" ]] || fail "Failed to derive CFBundleVersion from git history."
        log_info "Auto-injecting CFBundleVersion from git history: $BUILD_VERSION_OVERRIDE"
    else
        fail "Public distribution requires --build-version (no git history available to derive it)."
    fi
fi

build_args=(
    --output-dir "$OUTPUT_ROOT"
    --sign-identity "$SIGN_IDENTITY"
)

if [[ -n "$SHORT_VERSION_OVERRIDE" ]]; then
    build_args+=(--short-version "$SHORT_VERSION_OVERRIDE")
fi

if [[ -n "$BUILD_VERSION_OVERRIDE" ]]; then
    build_args+=(--build-version "$BUILD_VERSION_OVERRIDE")
fi

if [[ -n "$SPARKLE_FEED_URL" ]]; then
    build_args+=(--sparkle-feed-url "$SPARKLE_FEED_URL")
fi

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    build_args+=(--sparkle-public-ed-key "$SPARKLE_PUBLIC_ED_KEY")
fi

log_info "Building release app"
"${REPO_ROOT}/scripts/build-app.sh" "${build_args[@]}"

APP_PATH="${OUTPUT_ROOT}/PromptPanel.app"

[[ -d "$APP_PATH" ]] || fail "Built app not found: $APP_PATH"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_PATH}/Contents/Info.plist")"
ZIP_PATH="${OUTPUT_ROOT}/PromptPanel-${SHORT_VERSION}+${BUILD_VERSION}-macos.zip"
[[ -f "$ZIP_PATH" ]] || fail "Expected built zip archive not found: $ZIP_PATH"

# README/FAQ promise an Apple Silicon + Intel universal binary. A plain `swift build` only
# ever emits the host slice, so without this assertion an arm64-only archive could ship and
# fail to launch for every Intel user — a failure that is invisible on the build machine.
log_info "Verifying shipped architectures"
APP_BINARY_ARCHS="$(lipo -archs "${APP_PATH}/Contents/MacOS/PromptPanel")"
for required_arch in arm64 x86_64; do
    if [[ " $APP_BINARY_ARCHS " != *" $required_arch "* ]]; then
        fail "Built app is missing the ${required_arch} slice (found: ${APP_BINARY_ARCHS}); the distributed build must be universal."
    fi
done
log_info "App binary architectures: ${APP_BINARY_ARCHS}"

log_info "Verifying code signatures"
verify_bundle_signature "$APP_PATH" || fail "Code signature verification failed for $APP_PATH"

if [[ "$SIGN_IDENTITY" == "none" ]]; then
    BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Contents/Info.plist")"
    DESIGNATED_REQUIREMENT="$(codesign -dr - "$APP_PATH" 2>&1)"
    if ! grep -Fq "designated => identifier \"$BUNDLE_IDENTIFIER\"" <<<"$DESIGNATED_REQUIREMENT"; then
        fail "Ad-hoc build did not retain a stable designated requirement: $DESIGNATED_REQUIREMENT"
    fi
fi

# Assert that entitlements were actually embedded. The build script silently no-ops if the
# entitlements file is missing; without this check we would only discover that hardened
# runtime apps shipped without entitlements after signing regressions on a user machine.
# Run for every build mode — entitlements are embedded for both ad-hoc and signed.
EMBEDDED_ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null || true)"
if [[ -z "$EMBEDDED_ENTITLEMENTS" ]]; then
    fail "Built app has no embedded entitlements; ensure build-app.sh passes --entitlements when signing the outer bundle."
fi
# Enforce that library validation stays ENABLED (i.e. the entitlement is absent). build-app.sh
# re-signs Sparkle.framework and every embedded helper with the same identity as the app, so all
# loaded code shares one Team ID and passes hardened-runtime library validation without disabling
# it. Shipping com.apple.security.cs.disable-library-validation would needlessly widen the
# dylib-injection attack surface; keep it out of the distributed bundle.
if grep -Fq "com.apple.security.cs.disable-library-validation" <<<"$EMBEDDED_ENTITLEMENTS"; then
    fail "Built app ships com.apple.security.cs.disable-library-validation; library validation must stay enabled for distribution (all Sparkle code is re-signed with the app's identity, so the entitlement is unnecessary and weakens hardening)."
fi

# Assert the update metadata actually landed in the packaged Info.plist. build-app.sh injects it
# via PlistBuddy; a typo in the key name or a silently skipped injection would otherwise only
# surface once users are already stranded on a build that never checks for updates.
if [[ $PUBLIC_DISTRIBUTION -eq 1 ]]; then
    EMBEDDED_FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true)"
    EMBEDDED_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true)"
    [[ -n "$EMBEDDED_FEED_URL" ]] || fail "Built app has no SUFeedURL; it would never check for updates."
    [[ -n "$EMBEDDED_PUBLIC_KEY" ]] || fail "Built app has no SUPublicEDKey; Sparkle would refuse every update."
    [[ "$EMBEDDED_FEED_URL" == "$SPARKLE_FEED_URL" ]] || fail "Built app's SUFeedURL ($EMBEDDED_FEED_URL) does not match the requested feed ($SPARKLE_FEED_URL)."
    log_info "Update channel embedded: SUFeedURL=$EMBEDDED_FEED_URL"
fi

UNPACK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/promptpanel-unpacked.XXXXXX")"
cleanup_unpack() {
    rm -rf "$UNPACK_DIR"
}
trap cleanup_unpack EXIT

ditto -x -k "$ZIP_PATH" "$UNPACK_DIR"
verify_bundle_signature "${UNPACK_DIR}/PromptPanel.app" || fail "Code signature verification failed for unpacked ${UNPACK_DIR}/PromptPanel.app"

if [[ $PUBLIC_DISTRIBUTION -eq 1 ]]; then
    if ! codesign -dvv "$APP_PATH" 2>&1 | grep -q "Authority=Developer ID Application"; then
        fail "Public distribution precheck requires a Developer ID Application signature."
    fi
fi

if [[ $SKIP_SMOKE_LAUNCH -eq 0 ]]; then
    log_info "Running isolated startup smoke check"
    QA_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/promptpanel-ready.XXXXXX")"
    APP_SUPPORT_DIR="${QA_ROOT}/AppSupport"
    LOGS_DIR="${QA_ROOT}/Logs"
    APP_BINARY="${APP_PATH}/Contents/MacOS/PromptPanel"
    APP_LOG="${QA_ROOT}/app.log"

    stop_smoke_app() {
        if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
            kill "$APP_PID" >/dev/null 2>&1 || true
            wait "$APP_PID" >/dev/null 2>&1 || true
        fi
        unset APP_PID 2>/dev/null || true
    }

    cleanup_smoke() {
        stop_smoke_app
        rm -rf "$QA_ROOT"
    }

    trap 'cleanup_unpack; cleanup_smoke' EXIT

    env \
        PROMPTPANEL_ALLOW_EXISTING_INSTANCE=1 \
        PROMPTPANEL_APP_SUPPORT_DIR="$APP_SUPPORT_DIR" \
        PROMPTPANEL_LOGS_DIR="$LOGS_DIR" \
        "$APP_BINARY" >"$APP_LOG" 2>&1 &
    APP_PID=$!

    DATABASE_PATH="${APP_SUPPORT_DIR}/promptpanel.db"
    BACKUP_DIR="${APP_SUPPORT_DIR}/Backups"
    deadline=$((SECONDS + SMOKE_TIMEOUT_SECONDS))

    while (( SECONDS < deadline )); do
        if [[ -f "$DATABASE_PATH" ]] && [[ -n "$(find "$BACKUP_DIR" -maxdepth 1 -name '*.sqlite' -print -quit 2>/dev/null)" ]]; then
            break
        fi
        sleep 1
    done

    if [[ ! -f "$DATABASE_PATH" ]]; then
        log_warn "Smoke launch log:"
        tail -n 80 "$APP_LOG" >&2 || true
        fail "Smoke launch did not create the database at $DATABASE_PATH"
    fi

    if [[ -z "$(find "$BACKUP_DIR" -maxdepth 1 -name '*.sqlite' -print -quit 2>/dev/null)" ]]; then
        log_warn "Smoke launch log:"
        tail -n 80 "$APP_LOG" >&2 || true
        fail "Smoke launch did not create a startup backup under $BACKUP_DIR"
    fi

    if command -v sqlite3 >/dev/null 2>&1; then
        integrity_result="$(sqlite3 "$DATABASE_PATH" 'PRAGMA integrity_check;' 2>/dev/null || true)"
        [[ "$integrity_result" == "ok" ]] || fail "Smoke-launch database integrity check failed: ${integrity_result:-unknown}"
    else
        log_warn "sqlite3 is unavailable; skipped database integrity verification for the smoke-launch database."
    fi

    LATEST_BACKUP_PATH="$(find "$BACKUP_DIR" -maxdepth 1 -name '*.sqlite' -type f -print | sort | tail -n 1)"
    [[ -n "$LATEST_BACKUP_PATH" ]] || fail "Smoke launch did not produce a backup file that can be restored."

    log_info "Verifying backup restore path"
    stop_smoke_app
    RESTORE_APP_SUPPORT_DIR="${QA_ROOT}/RestoreTarget"
    "${REPO_ROOT}/scripts/restore-backup.sh" --target-dir "$RESTORE_APP_SUPPORT_DIR" "$LATEST_BACKUP_PATH"

    RESTORED_DATABASE_PATH="${RESTORE_APP_SUPPORT_DIR}/promptpanel.db"
    [[ -f "$RESTORED_DATABASE_PATH" ]] || fail "Restore drill did not create the restored database at $RESTORED_DATABASE_PATH"
    if command -v sqlite3 >/dev/null 2>&1; then
        restored_integrity_result="$(sqlite3 "$RESTORED_DATABASE_PATH" 'PRAGMA integrity_check;' 2>/dev/null || true)"
        [[ "$restored_integrity_result" == "ok" ]] || fail "Restored database integrity check failed: ${restored_integrity_result:-unknown}"
    fi

    cleanup_smoke
fi

log_info "Checks completed successfully"
if [[ $PUBLIC_DISTRIBUTION -eq 1 ]]; then
    log_warn "Public distribution precheck passed. Next run scripts/notarize-app.sh with the signed app, archive, and notarytool keychain profile."
fi
