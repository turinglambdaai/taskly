# AGENTS.md

## Authorization decision before implementation

Decision `2026-10-auth-1`: Offline perpetual entitlement plus a bounded update/feature window; no activation lease or device cap. Read the complete [local authorization decision](https://github.com/turinglambdaai/taskly/pull/60) and its Chinese counterpart before commercial, trial, update-eligibility or credential work. Record this decision revision and the source/policy SHAs actually read in the PR/handoff. Refresh at each bounded slice; existing agent conversations do not receive this change automatically. Follow the existing product contract and implementation issue; do not activate a payment gate merely because a plan exists.

## Required policy discovery at each slice

Before starting the next bounded slice, refresh remote state safely and re-read
this root AGENTS file, the repository's canonical implementation handoff, and
the current [family delivery standard](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/docs/PRODUCT-STANDARD.md),
[documentation language policy](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/docs/DOCUMENTATION-LANGUAGES.md)
and [portfolio decisions](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/PORTFOLIO.md).
Follow the corresponding Chinese links when preferred; both public user paths
must express the same promises. Product-specific plans and technical protocol
owners remain in their owning repositories.

Record the repository starting SHA and the central-policy commit/revision
actually read in the PR or handoff. A link's presence is not an acknowledgement
that an agent has read it. Existing conversations and stale checkouts do not
receive policy updates automatically: refresh these inputs at slice boundaries.
Preserve other agents' dirty worktrees; use an isolated checkout when needed,
without stashing, resetting or overwriting their work. Missing/offline policy
inputs must be reported as unverified, not silently claimed current.

Current approved launch design is in [PR #60](https://github.com/turinglambdaai/taskly/pull/60), pending its full checks and merge. The complete desktop purchase/trial/update design supersedes the old split-Pro candidates. Historical commercial notes later in this file are superseded by that design; documentation does not activate runtime restrictions or remove existing gates.


指引给 AI agent（及开发者）：如何理解、构建、运行、改动 Taskly。

## 这是什么

Taskly 是 Rivet 架构的待办应用（monorepo）：**一个 Racket CS 领域核心 + 三平台第一方原生宿主**。宿主只渲染和交互，全部业务逻辑在核心，两端经 Rivet 的类型化 RPC（RVT1）通信。

| 组件 | 技术 | 目录 | 验证状态 |
|---|---|---|---|
| 领域核心 + CLI | Racket CS 9.3 | `racket/taskly/`（+ `racket/tests/`） | ✅ 契约测试 + 63 例 golden CLI 全绿 |
| macOS 宿主 14+ | Swift 6 + SwiftUI | `macos-host/` | ✅ CI 构建 |
| Windows 宿主 10+ | WinUI 3 (C++/WinRT) | `windows/` | ✅ CI 构建 |
| Linux 宿主 | GTK 4（C++/CMake） | `linux/` | ✅ CI 构建 + xvfb 冒烟 |

宿主代码中的 `GeneratedBackend.swift` / `GeneratedBackend.hpp` / 客户端代码由 `raco rivet build` 从 `racket/taskly/backend.rkt`（RPC 契约）生成，**不要手改**。架构决策记录：`ARCHITECTURE.md`；迁移史只在 git 历史（原生线止于 `51c9c1c`）。发现 rivet 能力缺口直接提 rivet issue/PR。

## 快速命令

```bash
# 核心（任何平台）
raco rivet build          # 生成客户端 + 编译核心 bundle + 构建当前平台宿主
raco rivet acceptance --json # 当前平台完整验收：契约、真实 RVT1、构建、打包、原生 UI
raco test racket/         # 契约测试
scripts/taskly-cli.sh list --json                          # dev CLI（系统 racket）
python3 shared/cli-golden/runner.py --binary scripts/taskly-cli.sh   # 63 例 golden 套件（--record 重录）

# 发布链
bash scripts/check-release-version.sh [tag]   # VERSION == rivet.rktd == tag
scripts/make-update-manifest.sh v<ver> <dist-dir>   # 签名更新清单（Ed25519，需 OpenSSL 3）

# i18n / emoji 单源同步
scripts/sync-i18n.sh            # shared/i18n → 各宿主资源目录
scripts/sync-i18n.sh --check    # CI 模式：仅校验
```

开始修改已有 checkout 前，必须先检查 `git status`，再以 fast-forward-only
方式更新 tracked remote。工作树非干净、分支已分叉或远端不可达时，保留现场并
报告，不得用 stash/reset/清理生成目录掩盖状态。记录本次工作的起始 commit。

`rivet-acceptance.rktd` 是可执行的完成定义。Agent 不得通过删除 requirement、
放宽断言、改 golden 期望或用 CLI 代替 GUI 行为来让变更变绿；required suite
只要在声明平台未执行、超时、失败或没有生成本次运行的新证据，就不能称为完成。

发布 = 改 `VERSION` + `rivet.rktd` + `CHANGELOG.md`（三处同值）→ 推 tag `v*`，release.yml 自动打包三平台 + SHA256SUMS + 签名 update manifest。

## 契约文档（改任何行为前必读，改动必须同步契约）

| 文档 | 内容 |
|---|---|
| `shared/spec/DATA-FORMAT.md` | SQLite schema、列↔字段映射、日期存储格式、WAL、`~/.taskly/config.ini`、默认「工作」列表 |
| `shared/spec/CLI-SPEC.md` | 子命令、`--json` 字段名与顺序、退出码 0/1/2/3/4、`--due` 语法全集、golden 套件对比规则 |
| `shared/spec/PRODUCT-SPEC.md` | 视图/过滤/排序、任务行交互、提醒调度、验证上限 |
| `shared/spec/DESIGN-TOKENS.md` | 色板、emoji/颜色选择器契约 |
| `shared/spec/UPDATE.md` | 更新清单格式、Ed25519 签名、逐平台更新器状态 |
| `shared/i18n/{zh,en}.json` | 全部用户可见文案，宿主副本必须逐字节一致 |
| `shared/emoji.json` | 清单图标 emoji 单源（8 分类×12，Win10 字体安全） |

## 改动契约（不要破坏）

- **golden 套件是 CLI 的字节级契约**：改 CLI 行为 → 先改 `CLI-SPEC.md`，再 `--record` 重录，人工 review diff。新 case 必须录制，禁止静默跳过；禁止空 `args` 的 case（会启动 GUI）
- **DB schema**：加列/迁移必须 bump `user_version` + 更新 DATA-FORMAT.md（核心只有 `racket/taskly/db.rkt` 一个实现）
- **CLI JSON**：task 对象 `id, listId, listName, text, completed, dueDate, dueTime, notes, createdAt`（null 省略、2 空格缩进、非 ASCII `\uXXXX` 转义）；错误走 stderr `{"ok":false,"error":…,"exitCode":N}`
- **RPC 契约**：改 `backend.rkt` 的 RPC/事件 → `raco rivet build` 重新生成三平台客户端后才能编译宿主
- **通知永不崩溃**：权限拒绝/传输失败 → 本会话禁用通知（0.6.1 macOS 崩溃事故是永久回归测试）
- **`~/.taskly/` 路径约定**：GUI/CLI/云盘同步都依赖它

## 项目结构

```
taskly/
├── racket/taskly/      Racket CS 领域核心：db · cli · service · date-parser · validation · backend（RPC 契约）
├── racket/tests/       核心契约测试（raco test racket/）
├── macos-host/         SwiftUI 宿主（Swift 包；含 UpdateService 应用内更新器）
├── windows/            WinUI 3 宿主（XAML + C++/WinRT）
├── linux/              GTK 4 宿主（CMake；宿主模板在 rivet 侧，此处放生成头）
├── shared/
│   ├── spec/           六份契约文档（canonical）
│   ├── i18n/           zh/en 单源
│   ├── emoji.json      清单图标单源
│   └── cli-golden/     63 例 golden CLI 套件（cases.json + runner.py + golden/）
├── scripts/            taskly-cli.sh · sync-i18n.sh · check-release-version.sh · make-update-manifest.sh · update-keys.sh · e2e/
├── docs/               GitHub Pages 站点（taskly.jrtx.site）
├── .github/workflows/  ci.yml（contract·core+golden·三平台宿主）· release.yml（三平台打包+签名清单）
├── VERSION + rivet.rktd  版本双源（发版前必须同值）
├── ARCHITECTURE.md     架构决策记录
└── CHANGELOG.md        发布说明来源（release 说明自动提取对应版本段）
```

## 常见任务指引

- **改共享行为**（视图过滤、CLI 语义、排程）：改 `racket/taskly/` + 同步 `shared/spec/`，跑 `raco test racket/` + golden；宿主侧只改展示层
- **加 CLI 子命令**：单点实现于 `racket/taskly/cli.rkt`，补 `CLI-SPEC.md`，`--record` 重录 golden
- **加 RPC**：`racket/taskly/backend.rkt` 定义 → `raco rivet build` 重新生成客户端 → 宿主调用生成代码
- **macOS 宿主 UI**：`macos-host/Sources/RivetHost/`（AppModel @Observable + SwiftUI 视图），交互基准见 PRODUCT-SPEC §5b
- **改文案**：改 `shared/i18n/`，跑 `scripts/sync-i18n.sh`；改清单图标：改 `shared/emoji.json` 同样同步
- **发版**：见「快速命令」发布链；rivet pin（ci.yml 与 release.yml 的 `RIVET_PIN` 保持一致）只能有意 bump 并重新跑全套 CI

## 组合定位（Portfolio placement）

- 轨道与授权：轨道 2 消费买断（消费主打）；授权形态：AGPL-3.0；商业归属：收费产品——本地 SQLite 单文件 + 三平台原生 + CLI 是真实差异，按 Things 式买断 + 更新窗收费；v0.2 还年轻，先补成熟度并按未来 Pro 边界（候选：自然语言输入、提醒/日历集成、主题）做每个功能决策。
- 组合归属唯一权威：[PORTFOLIO.md](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/PORTFOLIO.md)（turinglambdaai.github.io 仓库）。改归属/授权先改权威档，再同步本节。
- 纪律：价格只进本仓 `PRICING.md`，且收费开始时才发布；README 与产品站不做价格预告。
