#!/bin/bash
set -e
APP="Glasswood.app/Contents"
rm -rf Glasswood.app
mkdir -p "$APP/MacOS" "$APP/Resources/scenes"

swiftc Glasswood.swift \
  -framework Cocoa -framework AVFoundation -framework AVKit \
  -o "$APP/MacOS/Glasswood"

# Bundle the scenes inside the app so it's fully self-contained
if [ -d assets ]; then
  cp assets/*.mp4 assets/*.jpg assets/manifest.json "$APP/Resources/scenes/" 2>/dev/null || true
  echo "📦 Bundled $(ls assets/*.mp4 2>/dev/null | wc -l | tr -d ' ') scenes."
else
  echo "⚠️  No assets/ folder — run ./prep.sh first."
fi

if [ -f icon.png ]; then
  mkdir -p Glasswood.iconset
  for s in 16 32 64 128 256 512; do
    sips -z $s $s icon.png --out Glasswood.iconset/icon_${s}x${s}.png &>/dev/null
  done
  sips -z 1024 1024 icon.png --out Glasswood.iconset/icon_512x512@2x.png &>/dev/null
  iconutil -c icns Glasswood.iconset -o "$APP/Resources/AppIcon.icns"
  rm -rf Glasswood.iconset
fi

cat > "$APP/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Glasswood</string>
  <key>CFBundleIdentifier</key><string>com.personal.glasswood</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Glasswood</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

codesign --force --deep --sign - Glasswood.app
xattr -cr Glasswood.app
echo "✅ Built Glasswood.app"
