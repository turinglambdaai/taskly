# Taskly

一个专注、原生的任务管理器。同一产品、同一 SQLite 数据文件、同一 agent CLI —— 每个平台都用原生技术实现。

**English** · [中文](README.zh-CN.md)

## 原生，而非跨平台

Taskly v1 是对基于 Avalonia 的 0.6.x 版本的完全原生重写。每个桌面平台都使用该平台的第一方 UI 技术栈 —— 不嵌入 WebView、不使用外来工具包、不再有上游 UI 回归（0.6.x 的 Windows 输入法重复字符和 macOS 通知崩溃是压垮骆驼的最后一根稻草）。

| 平台 | 技术栈 | 状态 | 目录 |
|---|---|---|---|
| macOS 14+ | Swift 6 + SwiftUI | ✅ 已验证：构建 + 24 个测试 + CLI 冒烟 | [apps/macos](apps/macos) |
| Windows 10+ | WinUI 3 (Windows App SDK) + .NET 10 | 源码完成，CI 构建 | [apps/windows](apps/windows) |
| Linux | Vala + GTK4 / libadwaita（编译为 C/GObject） | ✅ 原生构建 + 契约测试已验证 | [apps/linux](apps/linux) |
| iOS / iPadOS（下一步） | 复用 macOS SwiftUI 代码库 | 计划中 | — |
| Android（下一步） | Kotlin + Jetpack Compose | 计划中 | — |

架构决策详见 [ARCHITECTURE.md](ARCHITECTURE.md)。冻结的 Avalonia 0.6.x 实现保留在 `src/Taskly` 作为行为参照，原生 1.0 GA 后删除。

## 每个应用都包含

- **仿 macOS 提醒事项 UI** —— 智能视图（今天 / 计划 / 全部 / 完成）、emoji 图标 + 彩色的自定义列表、自然语言日期快速添加（`@10am`、`+1d`、`tomorrow`）、系统级到期通知、中英双语（运行时切换）、Anthropic 暖色调、明暗双主题。
- **单一数据文件** —— 所有任务存于一个 SQLite 文件（`~/.taskly/tasks.db`，WAL 模式），放进 iCloud / OneDrive / Dropbox 即可多设备同步。格式文档化且稳定：[DATA-FORMAT](shared/spec/DATA-FORMAT.md)。
- **同一二进制内的 agent CLI** —— `taskly list|add|update|done|rm|search|…`，支持 `--json`、稳定退出码、无头运行。规格：[CLI-SPEC](shared/spec/CLI-SPEC.md)。通过应用菜单（工具 ▸ 安装命令行工具）或 `taskly install-cli` 安装。

## 开发者指南

```
taskly/
├── apps/macos|windows|linux/   原生应用（各自独立构建系统）
├── shared/spec/                契约：产品 · 数据 · CLI · 设计令牌
├── shared/i18n/                中英文案单源（CI 校验各平台副本）
├── scripts/                    sync-i18n 等 CI 辅助脚本
├── src/Taskly/                 旧版 Avalonia 应用（冻结参照）
└── .github/workflows/          ci.yml（旧版）· native.yml（三平台原生）
```

三个应用**不共享任何代码**。它们共享契约（`shared/spec/`），由 CI 强制执行：一致的 CLI JSON/退出码、逐字节一致的 i18n、同一 DB schema（user_version 4）+ 三平台同步迁移。

### 构建

```bash
# macOS
cd apps/macos && swift build && swift test
scripts/make-app.sh            # Taskly.app

# Windows
dotnet build apps/windows/Taskly/Taskly.csproj -c Release

# Linux
cd apps/linux && meson setup build && meson compile -C build && meson test -C build
```

## 系统要求

- macOS：14 Sonoma 及以上（Apple Silicon + Intel）
- Windows：10 19041+ / 11
- Linux：任意 GTK4/libadwaita 桌面（推荐 GNOME 44+）

## 许可证

当前公开代码为 Apache-2.0；商业化授权模式确定中，见 [COMMERCIAL-CHECKLIST](COMMERCIAL-CHECKLIST.md)。
