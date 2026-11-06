#!/bin/zsh
# Regenerate the PromptPanel app icon set from make_icon.py.
# Outputs are written into this directory (master + iconset + .icns) and
# also synced into Sources/PromptPanel/Resources/{AppIcon.icns,Assets.xcassets/AppIcon.appiconset/}.

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
MASTER="${SCRIPT_DIR}/master_1024.png"
ICONSET="${SCRIPT_DIR}/AppIcon.iconset"
ICNS="${SCRIPT_DIR}/AppIcon.icns"
RES_DIR="${REPO_ROOT}/Sources/PromptPanel/Resources"
ASSET_DIR="${RES_DIR}/Assets.xcassets/AppIcon.appiconset"

python3 "${SCRIPT_DIR}/make_icon.py" "$MASTER"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16   16   "$MASTER" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32   32   "$MASTER" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32   32   "$MASTER" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64   64   "$MASTER" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128  128  "$MASTER" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256  256  "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$MASTER" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512  512  "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$MASTER" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"

cp "$ICNS" "${RES_DIR}/AppIcon.icns"
for f in "$ICONSET"/*.png; do
    cp "$f" "${ASSET_DIR}/"
done

echo "Icon assets refreshed at:"
echo "  ${RES_DIR}/AppIcon.icns"
echo "  ${ASSET_DIR}/"
