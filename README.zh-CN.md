# Taskly

一个专注的任务管理器。同一产品、同一 SQLite 数据文件、同一 agent CLI —— 一份共享的应用核心，每个桌面都用原生 UI。

**English** · [中文](README.zh-CN.md)

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

> **本分支是一次重建。** Taskly 正在以
> [Rivet](https://github.com/turinglambdaai/rivet)（我们自研的 Racket 应用框架）重建：
> 一份 Racket 领域核心，通过类型化 RPC 契约驱动各平台第一方原生 UI 薄壳。
> v1 原生版本线（SwiftUI / WinUI 3 / Vala-GTK4，其本身是对 0.6.x Avalonia
> 版本的重写）已归档在 `main`，可随时从 git 历史找回。决策与里程碑：
> [docs/RIVET-MIGRATION.md](docs/RIVET-MIGRATION.md)。

## 现状

| 部分 | 技术栈 | 状态 |
|---|---|---|
| 领域核心 | Racket（`racket/taskly/`），SQLite schema v4 | ✅ 完成，56 项契约测试三平台全绿 |
| Windows 宿主 | C++/WinRT + 嵌入式 Racket CS | M3 首个可运行（Taskly UI 跑在后端上） |
| macOS 宿主 | SwiftUI + 类型化客户端 | 移植中（[交接文档](docs/MACOS-HANDOFF.md)） |
| Linux 宿主 | GTK4 + 嵌入式 Racket CS | 首个可运行（智能视图、清单、增删改） |
| Agent CLI | Racket（M6） | 契约见 [CLI-SPEC](shared/spec/CLI-SPEC.md)，本分支尚未实现——日常 CLI 仍由已归档的 v1 应用提供 |

## 产品保留什么

- **Reminders 式 UI** —— 智能视图（今天 / 计划 / 全部 / 完成）、emoji 图标与
  配色的自定义清单、自然语言日期快速添加（`@10am`、`+1d`、`tomorrow`）、到期
  通知、中英双语、明暗主题。规格：[PRODUCT-SPEC](shared/spec/PRODUCT-SPEC.md)。
- **一份数据文件** —— 任务都在一个 SQLite 文件里（`~/.taskly/tasks.db`，WAL），
  可以直接放进 iCloud/OneDrive/Dropbox 同步。格式文档化且稳定：
  [DATA-FORMAT](shared/spec/DATA-FORMAT.md)。
- **Agent CLI** —— `taskly list|add|update|done|rm|search|…`，支持 `--json`、
  稳定退出码、无头运行。规格：[CLI-SPEC](shared/spec/CLI-SPEC.md)。

## 开发者指南

```
taskly/
├── rivet.rktd            Rivet 应用清单（backend 入口、协议 v1）
├── app/backend.rkt       Rivet 后端入口
├── racket/               领域核心 + 契约测试
├── windows/              C++/WinRT 宿主
├── macos-host/           SwiftUI 宿主
├── linux/                GTK4 宿主
├── shared/spec/          契约：产品 · 数据 · CLI · 设计令牌
├── shared/i18n/          中英文案单源
└── docs/                 迁移决策、交接文档、上游 backlog
```

### 构建

```bash
# 0) Racket CS 9.x，并把 rivet 以 linked 方式装好（rivet 检出分支决定
#    `raco rivet` 的行为；Taskly 需要 M1 named-record —— 已合入 rivet main）
cd ../rivet && raco pkg install --auto --no-docs --name rivet --link file://$PWD

raco rivet doctor --json     # 工具链自检
raco rivet build             # 编译后端 bundle + 本平台原生宿主
raco rivet dev               # 开发循环：自动重建 + 启动
raco test racket/            # 领域核心测试
```

各平台宿主需要第一方工具链（Windows App SDK / Xcode / GTK4 + CMake + 可嵌入
Racket CS）。完整地图见 [AGENTS.md](AGENTS.md)。

## 许可证

桌面核心采用 AGPL-3.0 —— 桌面应用开源，可自由使用、分叉与研究。后续商业化
部分（移动客户端与云同步）作为独立项目按各自条款发布；见
[COMMERCIAL-CHECKLIST](COMMERCIAL-CHECKLIST.md)。
