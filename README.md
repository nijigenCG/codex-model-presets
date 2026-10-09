# Codex 当前聊天模型快捷按钮

## 原生界面补丁（推荐）

独立 DMG 安装器，在 Codex 输入栏原模型选择器旁加入两个可配置按钮。未配置时：

- **Sol**：GPT-6.1 Sol · XHigh · Standard
- **Luna**：GPT-6 Luna · Max · Fast

直接调用 Codex 现有的模型设置和速度设置函数，使用当前聊天。按钮由原应用的 React 渲染；没有辅助功能模拟点击，也没有独立聊天界面。界面确认三个设置生效后，调用原应用的关闭菜单与输入焦点恢复函数。

### 安装与更新

请使用 [1.1.2 发布页](https://github.com/nijigenCG/codex-model-presets/releases/tag/native-patch-v1.1.2) 的 `Codex-Model-Presets-Patch-1.1.2.dmg`。旧版补丁在当前 Codex 上有兼容或启动缺陷，请升级补丁。

双击安装器，待当前回复结束后点击 **保存配置并安装**。安装器会备份完整原版应用，修改副本、更新 ASAR 完整性哈希并本地签名，通过签名、权限和系统进程加载检查后，退出并替换 Codex，再启动应用。安装器会观察新进程 5 秒；打不开或立即退出时，自动恢复原版并重新打开。

1.1.2 修复新版 Electron 的 `Failed to get integrity for validatable asar archive` 启动退出：同步更新 ASAR、Info.plist 和框架中的校验字典摘要，保留完整性校验。变更的框架和需要加载它的助手进行本地签名；原本允许加载本地框架的 Service 助手及其他未变更组件保留官方签名。清除本地签名不能持有的厂商权限声明，不修改系统 Gatekeeper 或 SIP。

Codex 更新后重新运行安装器。补丁通过界面语义定位代码，支持资源文件名变化；更大范围的结构变化会拒绝修改，需要发布适配版本。1.1.1 适配 26.1002.52244 的新版模型分派函数，保留原生模型 ID 转换、权限确认和选择结果。结构检查也覆盖旧版 26.928.21956；副本安装验证版本：**26.1002.52244 / Apple Silicon**。

### 配置两个按钮

安装器内可修改 **按钮名称、模型 ID、推理强度、Standard/Fast**，然后点击 **保存配置并安装**。名称或模型 ID 留空时采用该位置的默认值。**恢复默认配置** 会填回 Sol 和 Luna 的默认值，之后再保存安装。

配置保存在本机，Codex 更新后重新安装会沿用配置：

```text
~/Library/Application Support/Codex Model Presets Patch/presets.json
```

也可直接编辑该 JSON，然后重新安装；缺少文件、空文件、`{}`、空预设列表和空字段均使用默认值。支持配置正好两个按钮，例如：

```json
{
  "presets": [
    { "label": "Sol", "model": "gpt-6.1-sol", "effort": "xhigh", "speed": "standard" },
    { "label": "Luna", "model": "gpt-6-luna", "effort": "max", "speed": "fast" }
  ]
}
```

推理强度使用 `none/minimal/low/medium/high/xhigh/max/ultra` 中的一项；模型 ID 需要与当前 Codex 模型菜单一致。不支持的模型、强度或速度会让按钮置灰。配置嵌入本次应用补丁，修改 JSON 后需要重新安装才能生效。

点击 **卸载并恢复原版** 可恢复同版本官方整包及其原签名。备份保存在：

```text
~/Library/Application Support/Codex Model Presets Patch/Backups/
```

这是非官方客户端补丁，需使用 ad-hoc 签名，未经过 Apple 公证。macOS 可能要求允许打开安装器，或重新授权 Codex 的已有权限。补丁主应用无法保留需要 OpenAI 证书的应用组、推送和钥匙串组声明；依赖这些声明的功能尚未验证。若官方更新器无法更新，先卸载补丁恢复原版再更新。补丁不读取登录凭证。

### 构建与验证

安装器运行仅需 macOS 13+ 和 Apple Silicon；构建需要 Xcode Command Line Tools：

```sh
./build-native-patch.sh
```

生成的 DMG 只包含本项目的安装器和补丁，不包含 OpenAI 客户端代码。

按钮测试使用真实 React 和 jsdom，覆盖默认/自定义预设、Fast 别名、原生确认取消、失败、未确认状态、模型锁定和离开聊天时的异步回调：

```sh
cd native-patch/tests
npm install
npm test
```

完整应用副本的安装、实际启动、旧版受限权限回归、自定义配置重装和卸载验证（还需 Node.js、Python 3 与 rg）：

```sh
./native-patch/tests/integration.sh /Applications/ChatGPT.app
```

测试只替换 `.build/integration/` 中的应用副本，原版备份写入上面的备份目录。验证编译、匹配唯一性、混淆变量改名、生成代码语法、签名、受限权限拒绝、ASAR 内容与框架摘要、自定义配置注入和字节级恢复。实际启动测试使用临时 Electron 用户目录，运行 15 秒并检查主窗口完成加载、ready-to-show 和 React 渲染启动日志，结束后停止测试副本。安装前的系统加载检查仍使用挂起子进程；真实聊天按钮切换和焦点恢复需安装后验收。自动恢复针对打不开或进程立即退出，不能识别存活进程的白屏。

---

## 旧版菜单栏工具

macOS 菜单栏工具，通过辅助功能操作 ChatGPT/Codex 桌面端当前聊天的原生模型选择器。

它只保留两个日常预设：

- **Sol**：GPT-6.1 Sol · XHigh · Standard
- **Luna**：GPT-6 Luna · Max · Fast

## 使用

在 ChatGPT 桌面端打开目标 Codex 聊天，待当前回复结束后点击菜单栏中的 Sol 或 Luna。

切换器会设置并核对模型、推理强度和 Fast 状态，成功后关闭选择菜单并恢复 Codex 输入框焦点。右键任意按钮可退出切换器。

## 构建

要求 macOS、Apple Silicon 和 Xcode Command Line Tools：

```sh
./build.sh
open "dist/Codex 快捷模型.app"
```

构建脚本生成 ad-hoc 签名应用；源码仓库不包含编译产物。

首次使用需在 macOS「系统设置 → 隐私与安全性 → 辅助功能」中允许 **Codex 快捷模型**。系统可能另行请求控制 **System Events** 的权限，用于激活 ChatGPT 窗口。

## 工作方式与限制

- 工具使用 macOS Accessibility API 和 Codex 原生菜单，不修改 Codex 文件或全局配置。
- 支持当前中英文菜单，并按界面显示的强度档数定位预设。
- Codex 更新后若菜单标题或辅助功能层级变化，切换器会提示失败；此时可用 `⌃⇧M` 打开原生菜单手动切换。
- 只在当前聊天空闲时操作，避免切换正在生成回复的聊天。

## 许可证

MIT License，见 [LICENSE](LICENSE)。
