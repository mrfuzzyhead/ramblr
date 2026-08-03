#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
output_dir="${OUTPUT_DIR:-$project_dir/build}"
app_dir="$output_dir/Dictator.app"

cd "$project_dir"
swift build -c "$configuration"
binary_path="$(swift build -c "$configuration" --show-bin-path)/Dictator"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/Dictator"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"

# Bundle .env for local seeding when present (never commit it).
if [[ -f "$project_dir/.env" ]]; then
    cp "$project_dir/.env" "$app_dir/Contents/Resources/.env"
fi

codesign --force --deep --sign - "$app_dir"
touch "$app_dir"

echo "$app_dir"
