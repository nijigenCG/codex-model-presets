#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h:h}"
original="${1:-/Applications/ChatGPT.app}"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-presets-test.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT
export CODEX_MODEL_PRESETS_TEST_BACKUP_ROOT="$test_dir/Backups"
test_app="$test_dir/ChatGPT.app"
rejected_app="$test_dir/Rejected.app"
installer="$project_dir/dist/Codex 模型按钮补丁.app/Contents/MacOS/CodexModelPresetsPatch"
mkdir -p "$project_dir/.build/source-check"
cp "$project_dir/native-patch/tests/SourceChecks.swift" "$project_dir/.build/source-check/main.swift"
xcrun swiftc "$project_dir/native-patch/Configuration.swift" "$project_dir/native-patch/PatchCore.swift" "$project_dir/.build/source-check/main.swift" -o "$project_dir/.build/source-check/check"
"$project_dir/.build/source-check/check" "$original" "$project_dir/native-patch" "$project_dir/.build/source-check/patched.mjs"
node --check "$project_dir/.build/source-check/patched.mjs"
node "$project_dir/native-patch/tests/native-dispatch.cjs" "$project_dir/.build/source-check/patched.mjs"
ditto "$original" "$test_app"
"$installer" --check "$test_app"
"$installer" --install "$test_app"
"$installer" --check "$test_app"
backup_count=$(find "$CODEX_MODEL_PRESETS_TEST_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
node - "$test_app" <<'JS'
const fs = require("node:fs"), path = require("node:path");
const marker = JSON.parse(fs.readFileSync(`${process.argv[2]}/Contents/Resources/codex-model-presets-patch.json`));
const backup = path.dirname(marker.backupPath);
const stale = backup.slice(0, -64) + "0".repeat(64);
fs.mkdirSync(stale);
fs.writeFileSync(path.join(stale, "stale-backup"), "old version");
JS
"$installer" --install "$test_app"
[[ "$backup_count" == 1 && $(find "$CODEX_MODEL_PRESETS_TEST_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') == 1 ]]
"$installer" --startup-check "$test_app"
python3 "$project_dir/native-patch/tests/startup.py" "$test_app"
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
codesign -d --entitlements :- "$original" > "$test_dir/restricted.plist" 2>/dev/null
codesign --force --sign - --entitlements "$test_dir/restricted.plist" --preserve-metadata=flags,runtime "$rejected_app"
codesign --verify --deep --strict "$rejected_app"
if "$installer" --startup-check "$rejected_app"; then
  print -u2 '失败：未拒绝旧版受限权限导致的启动故障。'
  exit 1
fi
cat > "$test_dir/custom.json" <<'JSON'
{"presets":[{"label":"Astra","model":"gpt-6-astra","effort":"medium","speed":"standard"},{"label":"极速","model":"gpt-6-luna","effort":"max","speed":"fast"}]}
JSON
"$installer" --install "$rejected_app" "$test_dir/custom.json"
"$installer" --startup-check "$rejected_app"
# Services that already permit local frameworks retain OpenAI signatures.
codesign -dv "$rejected_app/Contents/Frameworks/Codex Framework.framework/Versions/Current/Helpers/Codex (Service).app" 2>&1 | rg 'TeamIdentifier=2DC432GLL2'
node "$project_dir/native-patch/tests/installed-config.cjs" "$rejected_app" "$test_dir/custom.json"
python3 "$project_dir/native-patch/tests/startup.py" "$rejected_app"
"$installer" --restore "$rejected_app"
codesign --verify --deep --strict "$rejected_app"
cmp "$original/Contents/Resources/app.asar" "$rejected_app/Contents/Resources/app.asar"
cmp "$original/Contents/Info.plist" "$rejected_app/Contents/Info.plist"
cmp "$original/Contents/MacOS/ChatGPT" "$rejected_app/Contents/MacOS/ChatGPT"
cmp "$original/Contents/_CodeSignature/CodeResources" "$rejected_app/Contents/_CodeSignature/CodeResources"
cmp "$original/Contents/Frameworks/Codex Framework.framework/Versions/Current/Codex Framework" "$rejected_app/Contents/Frameworks/Codex Framework.framework/Versions/Current/Codex Framework"
"$installer" --restore "$test_app"
codesign --verify --deep --strict "$test_app"
cmp "$original/Contents/Resources/app.asar" "$test_app/Contents/Resources/app.asar"
cmp "$original/Contents/Info.plist" "$test_app/Contents/Info.plist"
cmp "$original/Contents/MacOS/ChatGPT" "$test_app/Contents/MacOS/ChatGPT"
cmp "$original/Contents/_CodeSignature/CodeResources" "$test_app/Contents/_CodeSignature/CodeResources"
cmp "$original/Contents/Frameworks/Codex Framework.framework/Versions/Current/Codex Framework" "$test_app/Contents/Frameworks/Codex Framework.framework/Versions/Current/Codex Framework"
[[ -z $(find "$CODEX_MODEL_PRESETS_TEST_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -print -quit) ]]
print '备份复用、卸载清理、副本安装、实际启动和渲染、旧版受限权限拒绝、修复重装、自定义配置及字节级恢复验证通过。'
