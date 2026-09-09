#!/bin/bash
set -e
VERSION="${1:-1.0.0}"
[ -d Glasswood.app ] || { echo "Run ./build.sh first."; exit 1; }
rm -rf dmg "Glasswood-V${VERSION}.dmg"
mkdir -p dmg && cp -R Glasswood.app dmg/ && ln -s /Applications dmg/Applications
hdiutil create -volname "Glasswood ${VERSION}" -srcfolder dmg -ov -format UDZO \
  "Glasswood-V${VERSION}.dmg" >/dev/null
rm -rf dmg
echo "💿 Glasswood-V${VERSION}.dmg ready."
