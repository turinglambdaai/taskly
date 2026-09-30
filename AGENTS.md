# AGENTS.md

指引给 AI agent（及开发者）：如何理解、构建、运行、改动 Taskly。

> 本分支（`experiment/taskly-rivet`）是开发主线。`main` 是已归档的 v1 原生
> 实现（行为与视觉参照），不要再往它加功能。

## 这是什么

Taskly 是待办应用（同一产品、同一 SQLite 文件、同一 agent CLI 契约），正在
以 **Rivet**（自研 Racket 应用框架，github.com/turinglambdaai/rivet）重建：
一份 Racket 领域核心，通过 Rivet 的类型化 RPC（RVT1 协议）驱动各平台第一方
UI 薄壳。

| 平台宿主 | 技术栈 | 目录 | 状态 |
|---|---|---|---|
| Windows | C++/WinRT 宿主 + 嵌入式 Racket CS | `windows/` | M3 首个可运行（Taskly UI 跑在后端上） |
| macOS | SwiftUI 宿主 + 类型化客户端 | `macos-host/` | 移植中（见 `docs/MACOS-HANDOFF.md`） |
| Linux | GTK4 宿主 + 嵌入式 Racket CS | `linux/` | 首个可运行（智能视图/清单/增删改/快速添加） |
| agent CLI | Racket（领域层已就绪） | `racket/taskly/` | M6 待做—— rivet 分支尚无 CLI；日常 CLI 仍用 v1 原生应用 |

架构决策与里程碑（M0–M7）：`docs/RIVET-MIGRATION.md`。

## 快速命令

```bash
# 0) 前置：Racket CS 9.x，并把 rivet 以 linked 方式装好（切 rivet 检出分支
#    即切换 raco rivet 的行为；Taskly 需要 M1 named-record，已在 rivet main）
cd ../rivet && raco pkg install --auto --no-docs --name rivet --link file://$PWD

# 1) 工具链自检（Racket CS + cmake + 平台 UI 依赖）
raco rivet doctor --json

# 2) 构建 + 运行（生成宿主工程、编译后端 bundle、staged 布局）
raco rivet build
raco rivet dev          # 开发循环：改完自动重建 + 启动

# 3) 领域核心测试（三平台同套件）
raco test racket/

# 4) i18n 单源同步与校验（shared/i18n → 各平台资源）
scripts/sync-i18n.sh --check
```

Linux 宿主手编（不用 raco rivet 时）：`platform/linux/host/README.md`（在
rivet 仓库）；需要可嵌入 Racket CS（libracketcs.a + 3 个 boot 文件，标准
安装器不带，CI 用 minimal source+built-libraries 包）。

## 契约文档（改任何行为前必读，改动必须同步契约）

| 文档 | 内容 |
|---|---|
| `shared/spec/DATA-FORMAT.md` | SQLite schema v4、列↔字段映射、日期存储格式（`yyyy-MM-dd`/`HH:mm`/ISO-8601 本地时区）、WAL、`~/.taskly/config.ini`、默认「工作」列表（color = -4104388） |
| `shared/spec/CLI-SPEC.md` | CLI 子命令、`--json` 字段名与顺序、退出码 0/1/2/3/4、`--due` 语法全集（M6 实现的验收标准） |
| `shared/spec/PRODUCT-SPEC.md` | 视图/过滤/排序、任务行与详情交互、提醒调度、验证上限（1000/100/200/年份 1900–2100） |
| `shared/spec/DESIGN-TOKENS.md` | 暖色板（Pampas #F4F3EE + Crail #C15F3C，明暗两套）、10 色 iOS 调色板、6×8 emoji 分类 |
| `rivet.rktd` | Rivet 应用清单：backend 入口 `app/backend.rkt`、协议 v1、平台最低版本 |
| `shared/i18n/{zh,en}.json` | 全部用户可见文案（约 121 键），平台副本必须逐字节一致 |

## 改动契约（不要破坏）

- **DB schema**：`user_version = 4`。加列必须 bump 版本 + 更新 DATA-FORMAT.md + 三平台同一 release
- **RPC 面**：`racket/taskly/backend.rkt` 的 define-rpc 是宿主的唯一数据通道（open_database / load_snapshot / add_task / update_task / set_completed / delete_task / search_tasks / create_list / update_list / delete_list / get_settings / set_setting + `changed` 事件）。改签名 = 三端宿主 + 生成客户端同步改
- **CLI JSON 字段与退出码**（M6 时）：task 对象 `id, listId, listName, text, completed, dueDate, dueTime, notes, createdAt`；错误走 stderr `{"ok":false,"error":…,"exitCode:N}`
- **默认数据**：新库种下名为 `工作`（硬编码中文）的列表，icon `📋`，color ARGB int（有符号）
- **`~/.taskly/` 路径约定**：GUI/CLI/云盘同步都依赖它
- **Rivet 改动走上游**：Taskly 需要的可复用框架能力，PR 到 `turinglambdaai/rivet`（见 `docs/RIVET-LIB-BACKLOG.md`）

## 项目结构

```
taskly/
├── rivet.rktd          Rivet 应用清单（backend/module/entry/protocol）
├── app/backend.rkt     Rivet 后端入口（装配 racket/taskly 领域层）
├── racket/
│   ├── taskly/         Racket 领域核心（db/model/service/dateparser/rivet-schema/backend…）
│   └── tests/          核心契约测试（56 项，三平台同套件）
├── windows/            C++/WinRT 宿主（嵌入式 Racket CS + GeneratedBackend.hpp）
├── macos-host/         SwiftUI 宿主（SwiftPM，移植目标见 docs/MACOS-HANDOFF.md）
├── linux/              GTK4 宿主（CMake + 嵌入式 Racket CS；src/main.cpp 是 UI）
├── shared/
│   ├── spec/           四份契约文档（canonical）
│   ├── i18n/           zh.json / en.json 单源
│   └── assets/         图标源文件
├── scripts/            sync-i18n.sh、check-release-version.sh、e2e
├── docs/               RIVET-MIGRATION / MACOS-HANDOFF / RIVET-LIB-BACKLOG / 官网
└── ARCHITECTURE.md     架构决策记录
```

## 常见任务指引

- **改共享行为**（视图过滤、验证、文案）：先改 `shared/spec/` 或 `shared/i18n/`，再改 `racket/taskly/`，跑 `scripts/sync-i18n.sh` + `raco test racket/`，各宿主 UI 跟进
- **改领域逻辑**：`racket/taskly/`（service 层有真实 SQLite 行为）；测试必须绿
- **改宿主 UI**：windows `MainWindow.*`、macos-host `Sources/RivetHost/`、linux `linux/src/main.cpp`——宿主只做渲染与交互，业务一律走 RPC
- **加 RPC**：`racket/taskly/backend.rkt` define-rpc + schema（如需新 DTO）→ `raco rivet build` 重新生成三端客户端 → 宿主跟进
- **Rivet 框架缺能力**：先在 backlog 记一笔，PR 到 rivet；Taskly 分支只 pin commit，不改 vendored 副本
