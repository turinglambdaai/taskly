# Taskly

一款专注、键盘友好的跨平台任务管理器，覆盖 macOS、Windows 和 Linux——一个 Racket 核心驱动每个桌面的第一方原生宿主，附带面向 agent 的 CLI，数据就是单个本地 SQLite 文件。

[![release](https://img.shields.io/github/v/release/turinglambdaai/taskly)](https://github.com/turinglambdaai/taskly/releases/latest) ![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey) ![built with](https://img.shields.io/badge/built%20with-Rivet-9333ea) [![CI](https://github.com/turinglambdaai/taskly/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/taskly/actions/workflows/ci.yml) [![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

[English](README.md) · **中文**

Taskly 构建在 [Rivet](https://github.com/turinglambdaai/rivet) 之上：全部领域逻辑——SQLite 存储、排程、自然语言日期、校验、CLI——都在一个 Racket CS 核心里，每个桌面通过类型化 RPC 获得一个轻薄的第一方宿主。宿主只负责渲染和交互，所有逻辑都在后端。

| 桌面平台 | 宿主 |
|---|---|
| macOS 14+（Apple Silicon） | SwiftUI |
| Windows 10+（x64） | WinUI 3 |
| Linux（x64） | GTK 4 |

## 功能

- **Reminders 风格界面**——智能视图（今天 / 计划 / 全部 / 已完成），emoji 图标 + 12 色板的自定义清单，明暗主题跟随系统，中英双语实时切换。
- **自然语言快速添加**——输入 `明天买菜` 或 `standup @9am +1d`，回车前就能在实时预览 chip 里看到解析出的排程。
- **对齐 Reminders 的交互**——悬停行显示 今天/明天 一键调度 chip；⌘/⇧ 多选、批量操作、单条撤销横幅；↑/↓ 导航，Return 行内展开（标题、日期/时间 chip、备注），Esc 收起；已完成任务收进可折叠分组。
- **到期提醒通知**——60 秒轮询 + 启动检查，去重，超过三条合并为一条汇总。
- **单文件数据**——所有任务存在一个 SQLite 文件（`~/.taskly/tasks.db`，WAL），丢进 iCloud/OneDrive/Dropbox 即可同步。格式文档化且稳定：[DATA-FORMAT](shared/spec/DATA-FORMAT.md)。
- **面向 agent 的 CLI**——`taskly list|add|update|done|rm|search|mklist…`，`--json` 输出稳定、退出码固定、跨平台字节级一致（61 例 golden 套件钉死）。规格：[CLI-SPEC](shared/spec/CLI-SPEC.md)。
- **在线更新（三平台）**——启动时静默检查 + 设置里手动检查；后端验证 [更新清单](shared/spec/UPDATE.md)（Ed25519）并下载产物，宿主负责安装：macOS 原地换装 bundle，Windows 退出并换装安装目录，Linux 应用内下载、解压覆盖完成安装。

## 诚实差距

- **发布包暂不含独立 CLI 二进制**——CLI 目前从源码运行（见下节），打包分发在路线图上。

## 安装

到 [Releases](https://github.com/turinglambdaai/taskly/releases/latest) 下载对应平台的压缩包：`taskly-<version>-macos-arm64.zip`、`taskly-<version>-windows-x64.zip` 或 `taskly-<version>-linux-x64.tar.gz`。每个版本都带 `SHA256SUMS` 清单和签名的 `update-manifest.json`。

macOS 包为 ad-hoc 签名；首次启动如被 Gatekeeper 拦截，执行 `xattr -cr /Applications/Taskly.app` 即可。

Linux 需要 GTK 4 桌面（解压后运行 `RivetHost`；GTK 4 及其系统库是仅有的运行时依赖，其余全部内置）。

## 从源码使用 CLI

```bash
git clone https://github.com/turinglambdaai/taskly.git
cd taskly
raco pkg install --auto --no-docs https://github.com/turinglambdaai/rivet.git
racket racket/taskly/cli.rkt add "买牛奶" --due tomorrow --json
racket racket/taskly/cli.rkt install-cli   # 安装到 ~/.local/bin/taskly
```

## 从源码构建

需要 Racket CS 9.3+ 和对应桌面的原生工具链（macOS 用 Xcode/Swift，Linux 用 CMake + GTK 4 头文件，Windows 用 Windows App SDK）：

```bash
raco rivet build        # 生成客户端、编译核心、构建宿主
raco test racket/       # 62 个核心契约测试
python3 shared/cli-golden/runner.py --binary scripts/taskly-cli.sh   # 61 例 golden 套件
```

## 架构

```
┌─────────────────────────────┐            ┌────────────────────────────┐
│ 第一方宿主                   │            │ Racket CS 核心              │
│  SwiftUI · WinUI 3 · GTK 4  │◀── 类型化 ──▶│  db · 排程 · 校验 · 提醒    │
│  只做渲染和交互               │  RPC (RVT1)│  agent CLI（同一领域层）    │
│  内嵌 Racket CS 运行时        │            │                            │
└─────────────────────────────┘            └────────────────────────────┘
```

一套规格保证所有端一致：产品行为（[PRODUCT-SPEC](shared/spec/PRODUCT-SPEC.md)）、数据格式、CLI 契约、设计令牌、更新契约——都在 [shared/spec/](shared/spec/) 下。CI 在每次推送时用 golden 套件和字节级一致的 i18n 强制执行 CLI 契约。

## 许可证

[AGPL-3.0](LICENSE)。
