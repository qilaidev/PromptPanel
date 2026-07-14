#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
PACKAGE_ROOT="$REPO_ROOT"
APP_NAME="PromptPanel"
CONFIGURATION="release"
OUTPUT_ROOT="${REPO_ROOT}/dist"
SIGN_IDENTITY="none"
ARCHIVE=1
SHORT_VERSION_OVERRIDE=""
BUILD_VERSION_OVERRIDE=""
SPARKLE_FEED_URL=""
SPARKLE_PUBLIC_ED_KEY=""
BUNDLE_IDENTIFIER=""
DISPLAY_NAME_OVERRIDE=""

usage() {
    cat <<'EOF'
Usage: scripts/build-app.sh [options]

Options:
  --debug                 Build a debug app instead of release.
  --output-dir <path>     Output directory for the generated app and zip.
  --sign-identity <id>    codesign identity. Use "none" to skip signing.
  --no-archive            Skip zip archive creation.
  --short-version <ver>   Override CFBundleShortVersionString in the packaged app.
  --build-version <ver>   Override CFBundleVersion in the packaged app.
  --bundle-identifier <id>
                          Override CFBundleIdentifier in the packaged app.
  --display-name <name>   Override CFBundleDisplayName and CFBundleName.
  --sparkle-feed-url <u>  Inject SUFeedURL into the packaged app's Info.plist.
  --sparkle-public-ed-key <k>
                          Inject SUPublicEDKey into the packaged app's Info.plist.
  --help                  Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            CONFIGURATION="debug"
            shift
            ;;
        --output-dir)
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --sign-identity)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --no-archive)
            ARCHIVE=0
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
        --bundle-identifier)
            BUNDLE_IDENTIFIER="$2"
            shift 2
            ;;
        --display-name)
            DISPLAY_NAME_OVERRIDE="$2"
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
            echo "Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [[ ! -d "$PACKAGE_ROOT" ]]; then
    echo "Package root not found: $PACKAGE_ROOT" >&2
    exit 1
fi

if [[ -n "$SPARKLE_FEED_URL" && -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "Sparkle feed URL was provided, but SUPublicEDKey is missing." >&2
    exit 64
fi

if [[ -z "$SPARKLE_FEED_URL" && -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "Sparkle public key was provided, but SUFeedURL is missing." >&2
    exit 64
fi

if [[ -n "$SPARKLE_FEED_URL" && "$SPARKLE_FEED_URL" != https://* ]]; then
    echo "Sparkle feed URL must use https:// to prevent update-metadata tampering (got: ${SPARKLE_FEED_URL})." >&2
    exit 64
fi

mkdir -p "$OUTPUT_ROOT"

echo "Building ${APP_NAME} (${CONFIGURATION})..."
swift build --package-path "$PACKAGE_ROOT" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$PACKAGE_ROOT" -c "$CONFIGURATION" --show-bin-path)"

codesign_path() {
    local target_path="$1"
    local runtime_mode="${2:-off}"
    local stable_designated_requirement="${3:-off}"
    local entitlements_path="${4:-}"
    local args=(--force)

    if [[ "$SIGN_IDENTITY" == "none" ]]; then
        args+=(--sign -)
        if [[ "$stable_designated_requirement" == "on" ]]; then
            args+=(
                --identifier "$BUNDLE_IDENTIFIER"
                --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\""
            )
        fi
    else
        args+=(--timestamp --sign "$SIGN_IDENTITY")
        if [[ "$runtime_mode" == "runtime" ]]; then
            args+=(--options runtime)
        fi
    fi

    if [[ -n "$entitlements_path" && -f "$entitlements_path" ]]; then
        args+=(--entitlements "$entitlements_path")
    fi

    codesign "${args[@]}" "$target_path"
}

sign_framework_contents() {
    local framework_path="$1"
    local helper_paths=()
    local helper_path

    while IFS= read -r helper_path; do
        helper_paths+=("$helper_path")
    done < <(
        {
            find "$framework_path" -mindepth 1 -type d \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \) -print
            find "$framework_path" -mindepth 1 -type f \( -name '*.dylib' -o -name 'Autoupdate' \) -print
        } | awk '{ print length($0), $0 }' | sort -rn | cut -d' ' -f2-
    )

    # Every embedded executable (helper apps, XPC services, Autoupdate, nested
    # dylibs) and the framework bundle itself must carry the hardened-runtime
    # flag: Apple rejects any non-runtime executable inside a notarized app, and
    # signing each with the app's identity gives it the app's Team ID so the
    # framework passes hardened-runtime library validation without disabling it.
    # Helpers are signed deepest-first (paths pre-sorted by length) so nested
    # code is sealed before the bundle that contains it.
    for helper_path in "${helper_paths[@]}"; do
        codesign_path "$helper_path" runtime
    done

    codesign_path "$framework_path" runtime
}

strip_extended_attributes() {
    local target_path="$1"

    if command -v xattr >/dev/null 2>&1; then
        xattr -cr "$target_path" 2>/dev/null || true
    fi
}

APP_PATH="${OUTPUT_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${APP_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "$APP_PATH"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

cp "${PACKAGE_ROOT}/Sources/PromptPanel/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${CONTENTS_DIR}/Info.plist"
if [[ -n "$SHORT_VERSION_OVERRIDE" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION_OVERRIDE}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "$BUILD_VERSION_OVERRIDE" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION_OVERRIDE}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "$BUNDLE_IDENTIFIER" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_IDENTIFIER}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "$DISPLAY_NAME_OVERRIDE" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${DISPLAY_NAME_OVERRIDE}" "${CONTENTS_DIR}/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName ${DISPLAY_NAME_OVERRIDE}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "$SPARKLE_FEED_URL" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${SPARKLE_FEED_URL}" "${CONTENTS_DIR}/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :SUFeedURL ${SPARKLE_FEED_URL}" "${CONTENTS_DIR}/Info.plist"
fi
if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${SPARKLE_PUBLIC_ED_KEY}" "${CONTENTS_DIR}/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${SPARKLE_PUBLIC_ED_KEY}" "${CONTENTS_DIR}/Info.plist"
fi
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${CONTENTS_DIR}/Info.plist")"

cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod 755 "${MACOS_DIR}/${APP_NAME}"

APP_ICON_SRC="${PACKAGE_ROOT}/Sources/PromptPanel/Resources/AppIcon.icns"
if [[ -f "$APP_ICON_SRC" ]]; then
    cp "$APP_ICON_SRC" "${RESOURCES_DIR}/AppIcon.icns"
else
    echo "AppIcon.icns not found at $APP_ICON_SRC" >&2
    exit 1
fi

for bundle_path in "${BIN_DIR}"/*.bundle(N); do
    cp -R "$bundle_path" "${RESOURCES_DIR}/"
done

for framework_path in "${BIN_DIR}"/*.framework(N); do
    cp -R "$framework_path" "${FRAMEWORKS_DIR}/"
done

for dylib_path in "${BIN_DIR}"/*.dylib(N); do
    cp -R "$dylib_path" "${FRAMEWORKS_DIR}/"
done

if [[ -n "$(find "$FRAMEWORKS_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    if ! otool -l "${MACOS_DIR}/${APP_NAME}" | grep -q "@executable_path/../Frameworks"; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}"
    fi
fi

strip_extended_attributes "$APP_PATH"

for framework_path in "${FRAMEWORKS_DIR}"/*.framework(N); do
    sign_framework_contents "$framework_path"
done

for dylib_path in "${FRAMEWORKS_DIR}"/*.dylib(N); do
    codesign_path "$dylib_path" runtime
done

if [[ "$SIGN_IDENTITY" != "none" ]]; then
    echo "Signing app with identity: ${SIGN_IDENTITY}"
fi

ENTITLEMENTS_PATH="${PACKAGE_ROOT}/Sources/PromptPanel/Resources/PromptPanel.entitlements"
[[ -f "$ENTITLEMENTS_PATH" ]] || { echo "Entitlements file not found: $ENTITLEMENTS_PATH" >&2; exit 1; }
codesign_path "${APP_PATH}" runtime on "$ENTITLEMENTS_PATH"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

if [[ "$SIGN_IDENTITY" == "none" ]]; then
    DESIGNATED_REQUIREMENT="$(codesign -dr - "${APP_PATH}" 2>&1)"
    if ! grep -Fq "designated => identifier \"$BUNDLE_IDENTIFIER\"" <<<"$DESIGNATED_REQUIREMENT"; then
        echo "Ad-hoc signing did not produce the expected stable designated requirement:" >&2
        echo "$DESIGNATED_REQUIREMENT" >&2
        exit 1
    fi
fi

# SwiftPM resource-bundle discovery shim (Swift 6+ toolchain).
#
# SwiftPM's generated `Bundle.module` accessor resolves a target's resource
# bundle only at `Bundle.main.bundleURL/<Package>_<Target>.bundle`. For a
# packaged .app, `Bundle.main.bundleURL` is the bundle ROOT (sibling of
# Contents/), NOT Contents/Resources. Because our resource bundles live in
# Contents/Resources, the accessor's lookup fails and any dependency that
# touches `Bundle.module` at runtime (e.g. KeyboardShortcuts.Recorder, which
# lazily loads its localized bundle the first time the recorder is shown)
# hits `fatalError` and crashes the app.
#
# We must keep the real bundles under Contents/Resources so the code signature
# stays sealed and passes `codesign --verify --strict`; putting bundles (or even
# symlinks) at the root BEFORE signing trips "unsealed contents present in the
# bundle root" and fails signing. So we add relative symlinks at the app root
# AFTER all signing/verification. The root symlinks are unsealed, which is fine
# for locally installed / ad-hoc builds but means a notarized build would need
# a different (xcodebuild-based) resource layout.
for resource_bundle in "${RESOURCES_DIR}"/*.bundle(N); do
    bundle_basename="$(basename "$resource_bundle")"
    ln -sfn "Contents/Resources/${bundle_basename}" "${APP_PATH}/${bundle_basename}"
done

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${CONTENTS_DIR}/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${CONTENTS_DIR}/Info.plist")"

if [[ $ARCHIVE -eq 1 ]]; then
    ARCHIVE_PATH="${OUTPUT_ROOT}/${APP_NAME}-${SHORT_VERSION}+${BUILD_VERSION}-macos.zip"
    rm -f "$ARCHIVE_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
    echo "Archive created: ${ARCHIVE_PATH}"
fi

echo "App created: ${APP_PATH}"
