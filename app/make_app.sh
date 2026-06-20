#!/bin/sh
# Build AppleBasket.app from the SwiftPM binary and codesign it.
#
#   ./app/make_app.sh                 # ad-hoc signature (re-prompts TCC each rebuild)
#   ./app/make_app.sh "Apple Basket Dev"   # stable self-signed identity (recommended)
#
# Run from the repo root.

set -e

APP="AppleBasket.app"
BIN="AppleBasket"
IDENTITY="${1:--}"   # default: ad-hoc

swift build -c release --product "$BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/$BIN" "$APP/Contents/MacOS/$BIN"
cp app/Info.plist "$APP/Contents/Info.plist"

ENTITLEMENTS="app/entitlements.plist"
if [ -s "$ENTITLEMENTS" ]; then
    codesign --force --deep --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
else
    codesign --force --deep --sign "$IDENTITY" "$APP"
fi

echo "Built $APP"
echo "  signed with:   $IDENTITY"
echo "  entitlements:  $ENTITLEMENTS"
echo "  move it where you want it to live, e.g.:  mv $APP /Applications/"
