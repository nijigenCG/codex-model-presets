# Codex 当前聊天模型快捷按钮

macOS 菜单栏工具，通过辅助功能操作 ChatGPT/Codex 桌面端当前聊天的原生模型选择器。

它只保留三个日常预设：

- **Luna**：GPT-5.6 Luna · Max · Fast
- **Sol**：GPT-6 Sol · Extra High · Standard
- **Astra**：GPT-6 Astra · Medium · Standard

## 使用

在 ChatGPT 桌面端打开目标 Codex 聊天，待当前回复结束后点击菜单栏中的 Luna、Sol 或 Astra。

切换器会设置并核对模型、推理强度和 Fast 状态，成功后关闭选择菜单并恢复 Codex 输入框焦点。`◉` 菜单可退出切换器。

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
- Codex 更新后若菜单标题或辅助功能层级变化，切换器会提示失败；此时可用 `⌃⇧M` 打开原生菜单手动切换。
- 只在当前聊天空闲时操作，避免切换正在生成回复的聊天。

## 许可证

MIT License，见 [LICENSE](LICENSE)。
