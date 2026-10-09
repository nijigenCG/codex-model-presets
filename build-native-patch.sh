#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
app_dir="$project_dir/dist/Codex 模型按钮补丁.app"
dmg_dir="$project_dir/.build/native-patch-dmg"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$dmg_dir"
cp "$project_dir/native-patch/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/native-patch/presets.js" "$project_dir/native-patch/presets.css" "$app_dir/Contents/Resources/"
# Swift treats main.swift as the entrypoint when compiling multiple source files.
cp "$project_dir/native-patch/Installer.swift" "$project_dir/.build/main.swift"
xcrun swiftc -O -target arm64-apple-macosx13.0 "$project_dir/native-patch/Configuration.swift" "$project_dir/native-patch/PatchCore.swift" "$project_dir/.build/main.swift" -o "$app_dir/Contents/MacOS/CodexModelPresetsPatch"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
ditto "$app_dir" "$dmg_dir/Codex 模型按钮补丁.app"
cp "$project_dir/native-patch/使用说明.txt" "$dmg_dir/使用说明.txt"
patch_version=$(plutil -extract CFBundleShortVersionString raw -o - "$project_dir/native-patch/Info.plist")
hdiutil create -ov -format UDZO -volname 'Codex 模型按钮补丁' -srcfolder "$dmg_dir" "$project_dir/dist/Codex-Model-Presets-Patch-$patch_version.dmg"
print -r -- "$project_dir/dist/Codex-Model-Presets-Patch-$patch_version.dmg"
