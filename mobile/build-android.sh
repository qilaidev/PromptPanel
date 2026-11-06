#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
ANDROID_PROJECT_DIR="${SCRIPT_DIR}/android"
OUTPUT_DIR="${REPO_ROOT}/dist/release"

ANDROID_SDK="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
BUILD_TOOLS="${ANDROID_SDK}/build-tools/34.0.0"
PLATFORM_JAR="${ANDROID_SDK}/platforms/android-34/android.jar"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export PATH="${JAVA_HOME}/bin:${BUILD_TOOLS}:${PATH}"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${REPO_ROOT}/Sources/PromptPanel/Resources/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${REPO_ROOT}/Sources/PromptPanel/Resources/Info.plist")"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 64
            ;;
    esac
done

[[ -f "$PLATFORM_JAR" ]] || { echo "Android platform jar not found: $PLATFORM_JAR" >&2; exit 1; }
[[ -x "${BUILD_TOOLS}/aapt2" ]] || { echo "aapt2 not found in $BUILD_TOOLS" >&2; exit 1; }
[[ -x "${BUILD_TOOLS}/d8" ]] || { echo "d8 not found in $BUILD_TOOLS" >&2; exit 1; }
[[ -x "${BUILD_TOOLS}/zipalign" ]] || { echo "zipalign not found in $BUILD_TOOLS" >&2; exit 1; }
[[ -x "${BUILD_TOOLS}/apksigner" ]] || { echo "apksigner not found in $BUILD_TOOLS" >&2; exit 1; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/promptpanel-android-build.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

RES_DIR="${WORK_DIR}/res"
GEN_DIR="${WORK_DIR}/gen"
CLASSES_DIR="${WORK_DIR}/classes"
DEX_DIR="${WORK_DIR}/dex"
mkdir -p "${RES_DIR}/drawable" "$GEN_DIR" "$CLASSES_DIR" "$DEX_DIR" "$OUTPUT_DIR"

cp "${REPO_ROOT}/Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" \
   "${RES_DIR}/drawable/ic_launcher.png"

echo "[android-build] Compiling resources with aapt2..."
"${BUILD_TOOLS}/aapt2" compile --dir "$RES_DIR" -o "${WORK_DIR}/compiled_res.zip"

echo "[android-build] Linking APK resources and assets..."
"${BUILD_TOOLS}/aapt2" link \
    -I "$PLATFORM_JAR" \
    --manifest "${ANDROID_PROJECT_DIR}/AndroidManifest.xml" \
    -A "${ANDROID_PROJECT_DIR}/assets" \
    --java "$GEN_DIR" \
    --version-code "$BUILD_VERSION" \
    --version-name "$SHORT_VERSION" \
    -o "${WORK_DIR}/unaligned.apk" \
    "${WORK_DIR}/compiled_res.zip"

echo "[android-build] Compiling Java sources..."
javac -source 1.8 -target 1.8 \
    -bootclasspath "$PLATFORM_JAR" \
    -encoding UTF-8 \
    -d "$CLASSES_DIR" \
    "${GEN_DIR}/com/promptpanel/mobile/R.java" \
    "${ANDROID_PROJECT_DIR}/src/com/promptpanel/mobile/MainActivity.java"

echo "[android-build] Converting bytecode to DEX (all-ABI universal bytecode)..."
CLASS_FILES=("${CLASSES_DIR}"/com/promptpanel/mobile/*.class)
"${BUILD_TOOLS}/d8" \
    --release \
    --min-api 21 \
    --lib "$PLATFORM_JAR" \
    --output "$DEX_DIR" \
    "${CLASS_FILES[@]}"

(
    cd "$DEX_DIR"
    zip -q "${WORK_DIR}/unaligned.apk" classes.dex
)

echo "[android-build] Running zipalign (4-byte & page alignment)..."
"${BUILD_TOOLS}/zipalign" -p -f 4 "${WORK_DIR}/unaligned.apk" "${WORK_DIR}/aligned.apk"
"${BUILD_TOOLS}/zipalign" -c 4 "${WORK_DIR}/aligned.apk"

KEYSTORE_DIR="${REPO_ROOT}/dist/keystore"
mkdir -p "$KEYSTORE_DIR"
KEYSTORE_PATH="${KEYSTORE_DIR}/promptpanel-release.jks"
KEY_ALIAS="promptpanel"
KEY_PASS="promptpanel2026"

if [[ ! -f "$KEYSTORE_PATH" ]]; then
    echo "[android-build] Generating RSA-2048 release keystore..."
    keytool -genkeypair \
        -v \
        -keystore "$KEYSTORE_PATH" \
        -storetype PKCS12 \
        -alias "$KEY_ALIAS" \
        -keyalg RSA \
        -keysize 2048 \
        -sigalg SHA256withRSA \
        -validity 10000 \
        -storepass "$KEY_PASS" \
        -keypass "$KEY_PASS" \
        -dname "CN=PromptPanel Release, OU=Mobile, O=qilaidev, L=Shanghai, ST=Shanghai, C=CN" >/dev/null 2>&1
fi

FINAL_APK="${OUTPUT_DIR}/PromptPanel-${SHORT_VERSION}+${BUILD_VERSION}-android.apk"
echo "[android-build] Signing APK with V1 + V2 + V3 signature schemes..."
"${BUILD_TOOLS}/apksigner" sign \
    --ks "$KEYSTORE_PATH" \
    --ks-key-alias "$KEY_ALIAS" \
    --ks-pass "pass:${KEY_PASS}" \
    --key-pass "pass:${KEY_PASS}" \
    --v1-signing-enabled true \
    --v2-signing-enabled true \
    --v3-signing-enabled true \
    --out "$FINAL_APK" \
    "${WORK_DIR}/aligned.apk"

echo "[android-build] Verifying APK signature schemes..."
"${BUILD_TOOLS}/apksigner" verify --verbose --print-certs "$FINAL_APK"

echo "[android-build] Signed release APK ready: ${FINAL_APK}"
