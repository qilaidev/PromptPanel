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
mkdir -p "$RES_DIR" "$GEN_DIR" "$CLASSES_DIR" "$DEX_DIR" "$OUTPUT_DIR"

echo "[android-build] Generating multi-density & Adaptive Icon resources (mdpi ~ xxxhdpi + anydpi-v26)..."
python3 - "$RES_DIR" "${REPO_ROOT}/Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

res_dir = Path(sys.argv[1])
master_icon_path = Path(sys.argv[2])
master = Image.open(master_icon_path).convert("RGBA")

# 1. Generate legacy & round mipmap PNGs across all Android screen densities
densities = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

for folder, px in densities.items():
    d_dir = res_dir / folder
    d_dir.mkdir(parents=True, exist_ok=True)
    resized = master.resize((px, px), Image.LANCZOS)
    resized.save(d_dir / "ic_launcher.png", "PNG")

    # Circular mask for roundIcon
    mask = Image.new("L", (px * 4, px * 4), 0)
    md = ImageDraw.Draw(mask)
    pad = int(px * 4 * 0.04)
    md.ellipse((pad, pad, px * 4 - pad - 1, px * 4 - pad - 1), fill=255)
    mask = mask.resize((px, px), Image.LANCZOS)
    round_img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    round_img.paste(resized, (0, 0), mask)
    round_img.save(d_dir / "ic_launcher_round.png", "PNG")

# 2. Generate Adaptive Icon foreground & background (108dp per density)
fg_densities = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}

# Render high-res 1024x1024 foreground (cards inside safe 66/108 inner zone) and background
W = 1024
bg = Image.new("RGBA", (W, W), (0, 0, 0, 255))
top, bottom = (34, 37, 48), (13, 14, 18)
grad = Image.new("RGBA", (1, W), 0)
for y in range(W):
    t = y / (W - 1)
    e = 1 - (1 - t) ** 2
    r = int(top[0] * (1 - e) + bottom[0] * e)
    g = int(top[1] * (1 - e) + bottom[1] * e)
    b = int(top[2] * (1 - e) + bottom[2] * e)
    grad.putpixel((0, y), (r, g, b, 255))
bg = grad.resize((W, W))

fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
cx, cy = W // 2, W // 2
card_w = int(W * 0.42)
card_h = int(W * 0.072)
gap = int(W * 0.036)
radius = int(card_h * 0.44)

top_y = cy - card_h - gap - card_h // 2
mid_y = cy - card_h // 2
bot_y = cy + gap + card_h // 2

panel_pad = int(W * 0.042)
panel_box = (
    cx - card_w // 2 - panel_pad,
    top_y - card_h // 2 - panel_pad,
    cx + card_w // 2 + panel_pad,
    bot_y + card_h // 2 + panel_pad,
)
pd = ImageDraw.Draw(fg)
pd.rounded_rectangle(panel_box, radius=int(W * 0.03), fill=(255, 255, 255, 16), outline=(255, 255, 255, 38), width=3)

cards = [
    (top_y, int(card_w * 1.00), (236, 238, 246, 255), True),
    (mid_y, int(card_w * 0.86), (186, 192, 210, 255), False),
    (bot_y, int(card_w * 0.70), (138, 145, 166, 255), False),
]
for y, w, color, selected in cards:
    x0, x1 = cx - w // 2, cx + w // 2
    y0, y1 = y - card_h // 2, y + card_h // 2
    pd.rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=color)
    if selected:
        sw = int(card_h * 0.22)
        sp = int(card_h * 0.18)
        pd.rounded_rectangle((x0 + sp, y0 + sp, x0 + sp + sw, y1 - sp), radius=sw // 2, fill=(124, 140, 248, 255))
        dr = int(card_h * 0.10)
        dcx = x1 - int(card_h * 0.55)
        pd.ellipse((dcx - dr, y - dr, dcx + dr, y + dr), fill=(124, 140, 248, 110))

for folder, px in fg_densities.items():
    d_dir = res_dir / folder
    d_dir.mkdir(parents=True, exist_ok=True)
    bg.resize((px, px), Image.LANCZOS).save(d_dir / "ic_launcher_background.png", "PNG")
    fg.resize((px, px), Image.LANCZOS).save(d_dir / "ic_launcher_foreground.png", "PNG")

# 3. Write mipmap-anydpi-v26 adaptive-icon XMLs
anydpi = res_dir / "mipmap-anydpi-v26"
anydpi.mkdir(parents=True, exist_ok=True)
adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
(anydpi / "ic_launcher.xml").write_text(adaptive_xml, encoding="utf-8")
(anydpi / "ic_launcher_round.xml").write_text(adaptive_xml, encoding="utf-8")
PY

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
    "${ANDROID_PROJECT_DIR}/src/com/promptpanel/mobile/"*.java

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
KEYSTORE_PATH="${ANDROID_KEYSTORE_PATH:-${KEYSTORE_DIR}/promptpanel-release.jks}"
KEY_ALIAS="${ANDROID_KEY_ALIAS:-promptpanel}"
KEY_PASS="${ANDROID_KEY_PASS:-promptpanel2026}"

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
