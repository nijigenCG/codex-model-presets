#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h:h}"
original="${1:-/Applications/ChatGPT.app}"
test_app="$project_dir/.build/integration/ChatGPT.app"
rejected_app="$project_dir/.build/integration/Rejected.app"
installer="$project_dir/dist/Codex 模型按钮补丁.app/Contents/MacOS/CodexModelPresetsPatch"
mkdir -p "$project_dir/.build/integration"
mkdir -p "$project_dir/.build/source-check"
cp "$project_dir/native-patch/tests/SourceChecks.swift" "$project_dir/.build/source-check/main.swift"
xcrun swiftc "$project_dir/native-patch/Configuration.swift" "$project_dir/native-patch/PatchCore.swift" "$project_dir/.build/source-check/main.swift" -o "$project_dir/.build/source-check/check"
"$project_dir/.build/source-check/check" "$original" "$project_dir/native-patch"
if [[ -e "$test_app" || -e "$rejected_app" ]]; then
  print -u2 '测试副本已存在，请另行移走 .build/integration 中的应用副本后重试。'
  exit 1
fi
ditto "$original" "$test_app"
"$installer" --check "$test_app"
"$installer" --install "$test_app"
"$installer" --check "$test_app"
"$installer" --startup-check "$test_app"
# Reproduce 1.0's valid signature but AMFI-rejected vendor entitlements.
# Use a fresh inode: signing an executable just loaded by AMFI can yield EPERM.
ditto "$test_app" "$rejected_app"
node - "$rejected_app" <<'JS'
const fs = require("node:fs");
const path = `${process.argv[2]}/Contents/Resources/codex-model-presets-patch.json`;
const marker = JSON.parse(fs.readFileSync(path));
marker.patchVersion = "1.0.0";
delete marker.configurationHash;
fs.writeFileSync(path, JSON.stringify(marker));
JS
codesign -d --entitlements :- "$original" > "$project_dir/.build/integration/restricted.plist" 2>/dev/null
codesign --force --sign - --entitlements "$project_dir/.build/integration/restricted.plist" --preserve-metadata=flags,runtime "$rejected_app"
codesign --verify --deep --strict "$rejected_app"
if "$installer" --startup-check "$rejected_app"; then
  print -u2 '失败：未拒绝旧版受限权限导致的启动故障。'
  exit 1
fi
cat > "$project_dir/.build/integration/custom.json" <<'JSON'
{"presets":[{"label":"Astra","model":"gpt-6-astra","effort":"medium","speed":"standard"},{"label":"极速","model":"gpt-6-luna","effort":"max","speed":"fast"}]}
JSON
"$installer" --install "$rejected_app" "$project_dir/.build/integration/custom.json"
"$installer" --startup-check "$rejected_app"
# Nested frameworks and helpers must retain OpenAI signatures.
codesign -dv "$rejected_app/Contents/Frameworks/Codex Framework.framework" 2>&1 | rg 'TeamIdentifier=2DC432GLL2'
node "$project_dir/native-patch/tests/installed-config.cjs" "$rejected_app" "$project_dir/.build/integration/custom.json"
"$installer" --restore "$rejected_app"
codesign --verify --deep --strict "$rejected_app"
cmp "$original/Contents/Resources/app.asar" "$rejected_app/Contents/Resources/app.asar"
cmp "$original/Contents/Info.plist" "$rejected_app/Contents/Info.plist"
cmp "$original/Contents/MacOS/ChatGPT" "$rejected_app/Contents/MacOS/ChatGPT"
cmp "$original/Contents/_CodeSignature/CodeResources" "$rejected_app/Contents/_CodeSignature/CodeResources"
"$installer" --restore "$test_app"
codesign --verify --deep --strict "$test_app"
cmp "$original/Contents/Resources/app.asar" "$test_app/Contents/Resources/app.asar"
cmp "$original/Contents/Info.plist" "$test_app/Contents/Info.plist"
cmp "$original/Contents/MacOS/ChatGPT" "$test_app/Contents/MacOS/ChatGPT"
cmp "$original/Contents/_CodeSignature/CodeResources" "$test_app/Contents/_CodeSignature/CodeResources"
print '副本安装、旧版启动故障复现和拒绝、修复重装、自定义配置、嵌套官方签名及字节级恢复验证通过。'
