#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h:h}"
original="${1:-/Applications/ChatGPT.app}"
test_app="$project_dir/.build/integration/ChatGPT.app"
installer="$project_dir/dist/Codex 模型按钮补丁.app/Contents/MacOS/CodexModelPresetsPatch"
mkdir -p "$project_dir/.build/integration"
mkdir -p "$project_dir/.build/source-check"
cp "$project_dir/native-patch/tests/SourceChecks.swift" "$project_dir/.build/source-check/main.swift"
xcrun swiftc "$project_dir/native-patch/PatchCore.swift" "$project_dir/.build/source-check/main.swift" -o "$project_dir/.build/source-check/check"
"$project_dir/.build/source-check/check" "$original" "$project_dir/native-patch"
if [[ -e "$test_app" ]]; then
  print -u2 '测试副本已存在，请另行移走 .build/integration/ChatGPT.app 后重试。'
  exit 1
fi
ditto "$original" "$test_app"
"$installer" --check "$test_app"
"$installer" --install "$test_app"
"$installer" --check "$test_app"
"$installer" --install "$test_app"
"$installer" --restore "$test_app"
codesign --verify --deep --strict "$test_app"
cmp "$original/Contents/Resources/app.asar" "$test_app/Contents/Resources/app.asar"
cmp "$original/Contents/Info.plist" "$test_app/Contents/Info.plist"
cmp "$original/Contents/_CodeSignature/CodeResources" "$test_app/Contents/_CodeSignature/CodeResources"
print '副本安装、重复安装、卸载、官方签名及字节级恢复验证通过。'
