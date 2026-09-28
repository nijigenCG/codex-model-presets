#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
app_dir="$project_dir/dist/Codex 快捷模型.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
xcrun swiftc -O -target arm64-apple-macosx15.0 "$project_dir/ModelPresets.swift" -o "$app_dir/Contents/MacOS/CodexModelPresets"
codesign --force --sign - "$app_dir"
print -r -- "$app_dir"
