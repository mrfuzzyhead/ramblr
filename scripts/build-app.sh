#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
output_dir="${OUTPUT_DIR:-$project_dir/build}"
app_dir="$output_dir/Ramblr.app"

cd "$project_dir"
swift build -c "$configuration"
binary_path="$(swift build -c "$configuration" --show-bin-path)/Ramblr"

rm -rf "$app_dir" "$output_dir/Dictator.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

cp "$binary_path" "$app_dir/Contents/MacOS/Ramblr"
chmod +x "$app_dir/Contents/MacOS/Ramblr"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$app_dir/Contents/PkgInfo"

# Bundle .env for local seeding when present (never commit it).
if [[ -f "$project_dir/.env" ]]; then
    cp "$project_dir/.env" "$app_dir/Contents/Resources/.env"
fi

# Prefer a stable signing identity so macOS TCC (Accessibility, Input Monitoring)
# and Keychain trust survive reinstalls. Ad-hoc signing gets a new identity each build.
codesign_identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$codesign_identity" ]]; then
    codesign_identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
            | head -n 1
    )"
fi
if [[ -z "$codesign_identity" ]]; then
    codesign_identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
            | head -n 1
    )"
fi
if [[ -n "$codesign_identity" ]]; then
    echo "Signing with: $codesign_identity"
    codesign --force --deep --sign "$codesign_identity" "$app_dir"
else
    echo "Signing ad-hoc (TCC permissions may reset on each install)"
    codesign --force --deep --sign - "$app_dir"
fi
touch "$app_dir"

echo "$app_dir"
