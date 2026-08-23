#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)"
SOURCE_IMAGE="${1:-$ROOT/assets/branding/printerbridge-app-icon.svg}"
APP_ICON_SET_DIR="$ROOT/apps/macos/PrinterBridgeApp/Resources/Assets.xcassets/AppIcon.appiconset"
GENERATED_DIR="$ROOT/assets/branding/generated"
DOCS_ASSET_DIR="$ROOT/docs/assets"
RENDERED_IMAGE="$GENERATED_DIR/printerbridge-app-icon-rendered.png"
PREVIEW_IMAGE="$GENERATED_DIR/printerbridge-app-icon-preview.png"

if [ ! -f "$SOURCE_IMAGE" ]; then
  echo "Icon source image not found at: $SOURCE_IMAGE" >&2
  exit 1
fi

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required to render the SVG app icon (brew install librsvg)." >&2
  exit 1
fi

mkdir -p "$APP_ICON_SET_DIR"
mkdir -p "$GENERATED_DIR"
mkdir -p "$DOCS_ASSET_DIR"

rsvg-convert --width 1024 --height 1024 --keep-aspect-ratio "$SOURCE_IMAGE" --output "$RENDERED_IMAGE"
cp "$RENDERED_IMAGE" "$PREVIEW_IMAGE"

generate_icon() {
  size="$1"
  name="$2"
  sips -z "$size" "$size" "$RENDERED_IMAGE" --out "$APP_ICON_SET_DIR/$name" >/dev/null
}

generate_icon 16 icon_16x16.png
generate_icon 32 icon_16x16@2x.png
generate_icon 32 icon_32x32.png
generate_icon 64 icon_32x32@2x.png
generate_icon 128 icon_128x128.png
generate_icon 256 icon_128x128@2x.png
generate_icon 256 icon_256x256.png
generate_icon 512 icon_256x256@2x.png
generate_icon 512 icon_512x512.png
generate_icon 1024 icon_512x512@2x.png

cp "$RENDERED_IMAGE" "$DOCS_ASSET_DIR/printer-bridge-icon.png"
cp "$SOURCE_IMAGE" "$DOCS_ASSET_DIR/printer-bridge-icon.svg"
sips -z 500 500 "$RENDERED_IMAGE" --out "$ROOT/assets/branding/printer-bridge-icon-transparent.png" >/dev/null
cp "$ROOT/assets/branding/printer-bridge-icon-transparent.png" "$DOCS_ASSET_DIR/printer-bridge-icon-transparent.png"
sips -z 232 232 "$RENDERED_IMAGE" --out "$DOCS_ASSET_DIR/printer-bridge-icon-transparent-232.png" >/dev/null

echo "Preview written to: $PREVIEW_IMAGE"
