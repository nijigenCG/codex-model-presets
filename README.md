# Codex 当前聊天模型快捷按钮

## 原生界面补丁（推荐）

独立 DMG 安装器，在 Codex 输入栏原模型选择器旁加入 **Sol** 和 **Luna** 两个按钮：

- **Sol**：GPT-6.1 Sol · XHigh · Standard
- **Luna**：GPT-6 Luna · Max · Fast

直接调用 Codex 现有的模型设置和速度设置函数，使用当前聊天。按钮由原应用的 React 渲染；没有辅助功能模拟点击，也没有独立聊天界面。界面确认三个设置生效后，调用原应用的关闭菜单与输入焦点恢复函数。

### 安装与更新

打开 `Codex-Model-Presets-Patch-1.0.0.dmg`，双击安装器，待当前回复结束后点击 **安装补丁**。安装器会备份完整原版应用，修改副本、更新 ASAR 完整性哈希并本地签名，校验通过后退出并替换 Codex，再启动应用。

Codex 更新后重新运行安装器。补丁通过界面语义定位代码，支持资源文件名变化；更大范围的结构变化会拒绝修改，需要发布适配版本。当前已验证版本：**26.928.21956 / Apple Silicon**。

点击 **卸载并恢复原版** 可恢复同版本官方整包及其原签名。备份保存在：

```text
~/Library/Application Support/Codex Model Presets Patch/Backups/
```

这是非官方客户端补丁，需使用 ad-hoc 签名，未经过 Apple 公证。macOS 可能要求允许打开安装器，或重新授权 Codex 的已有权限。若官方更新器无法更新，先卸载补丁恢复原版再更新。账号不支持目标模型、强度或 Fast，或聊天锁定模型时，按钮不可用。补丁不读取登录凭证。

### 构建与验证

安装器运行仅需 macOS 13+ 和 Apple Silicon；构建需要 Xcode Command Line Tools：

```sh
./build-native-patch.sh
```

生成的 DMG 只包含本项目的安装器和补丁，不包含 OpenAI 客户端代码。

按钮测试使用真实 React 和 jsdom，覆盖两个预设、Fast 别名、原生确认取消、失败、未确认状态、模型锁定和离开聊天时的异步回调：

```sh
cd native-patch/tests
npm install
npm test
```

完整应用副本的安装/重复安装/卸载验证：

```sh
./native-patch/tests/integration.sh /Applications/ChatGPT.app
```

测试只操作 `.build/integration/ChatGPT.app` 副本。发布前已通过编译、签名、ASAR 文件完整性和副本回滚检查；真实 Codex 聊天的按钮点击仍需用户安装后验收。

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
