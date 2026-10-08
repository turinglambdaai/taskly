# Taskly on MacBook Pro — 开发交接 / Handoff

> 写给要在 MacBook 上继续 Taskly×Rivet 开发的人（或 AI 会话）。
> 一切都已推送；这里是可以直接照做的步骤和当前状态的完整地图。

## 仓库与分支

| 仓库 | 分支 | 用途 |
|---|---|---|
| `turinglambdaai/taskly` | `main`（开发主线） | Rivet 项目布局：`rivet.rktd` + `racket/taskly/`（Racket 领域核心，M0 ✅）+ `app/backend.rkt`（Rivet 后端入口）+ `windows/`（C++/WinRT 宿主）+ `macos-host/`（SwiftUI 宿主脚手架） |
| `turinglambdaai/rivet` | `main` | named-record API 已进 rivet main（PR #72 + #78；issue #92 已验证关闭）——**不再需要切任何 rivet 分支**，linked main 即可 |

`main` 即 Rivet 重建主线。

## MacBook 首次环境搭建

```bash
# 1. Racket CS 9.x（或更新）—— rivet doctor 会校验
#    https://download.racket-lang.org/

# 2. Xcode + SwiftUI 工具链（macOS 宿主编译用）

# 3. 克隆两个仓库
git clone https://github.com/turinglambdaai/taskly.git
git clone https://github.com/turinglambdaai/rivet.git
cd rivet
# 4. linked 安装 rivet（开发 rivet 本身的工作流，改 rivet 代码即时生效）
raco pkg install --auto --link file://$(pwd)

# 5. 工具链自检
raco rivet doctor    # 期望: Racket CS + Xcode + macOS 14 SDK 全绿

# 6. 构建并启动 Taskly macOS 宿主（hello 级验证）
cd ../taskly
raco rivet build     # 或 raco rivet dev（开发循环：改完自动重建+启动）
```

## 当前状态与下一步工作

### 已完成（Windows 侧验证过）
- M0：整个 Taskly 领域层的 Racket 实现（`racket/taskly/`，1055 行，SQLite v4 真实行为）三平台测试通过
- Windows：C++/WinRT 宿主在 `windows/`，`raco rivet build` 在 pinned rivet（f37908f）下直接通过（2026-10-08 CI 实证，「vcxproj 需适配」已过时）；CI 有 windows-host job 看守

### macOS 端任务（你的 MacBook 上的工作顺序）

1. ~~**跑通 hello 宿主**~~ 已完成
2. ~~**接 Taskly 后端**~~ 已完成
3. ~~**移植 Taskly SwiftUI UI**~~ **已完成（2026-10-02）**——Reminders 式全量 UI 落在 `macos-host/Sources/RivetHost/`：智能视图/清单增删改/快速添加（解析预览）/行内展开/多选/键盘流/撤销横幅/搜索/明暗主题/中英切换；数据面全部走 GeneratedBackend.swift 类型化客户端。`raco rivet build && raco rivet dev` 即可运行。待做：提醒通知调度（ReminderService 对应物）、菜单栏速添、CLI 安装菜单项
4. ~~给 rivet 提 PR：移植 named-record API~~ **已完成**——rivet main 经 PR #72/#78 自带 define-record/Optional/嵌套/枚举（issue #92 已验证关闭），racket/taskly 直接用库 API
5. ~~**M6**：把 agent-facing CLI 用 Racket 重写~~ **已完成（2026-10-02）**——`racket/taskly/cli.rkt`，`python3 shared/cli-golden/runner.py --binary <cli>` 61/61；快速添加语法已收口到后端 `parse_quick_add` RPC（三宿主共用一份解析）。剩余：macOS 提醒通知（PRODUCT-SPEC §9）、宿主内嵌 CLI 双模式打包（M7）、Windows/Linux 交互 parity（M3/M5）

### 已知坑（前人踩过，别再踩）

- **Sep 21 的 Windows 嵌入崩溃**：WinUI 进程内嵌 Racket CS 反复崩溃未收敛。macOS 的 SwiftUI+RivetClient 路径是 rivet 自己维护的（`platform/macos/`），风险完全不同——但 `raco rivet dev` 首次跑通前不要假设它一定行
- **raco rivet = linked checkout 的代码**：rivet 仓库切分支即切换 `raco rivet` 的行为。Taskly 的 racket 核心自带的 `racket/taskly/rivet-schema.rkt` 不依赖 rivet 分支（它就是那段 named-record 实现）；只有把该层移植进 rivet main 之前，别指望 rivet 库直接提供 define-record
- **Windows 端不支持 .NET 客户端**：PR #50/#51 被 rivet 维护方向否决（C++/WinRT + 进程内 Racket CS 才是方向）；Taskly 的 windows/ C# 宿主已按此删除，windows/ 现在是 C++ 宿主脚手架
- Taskly 的 racket 核心自带 `racket/taskly/rivet-schema.rkt`（named-record 层），正常无需任何 rivet 分支切换；若 `raco rivet build` 报 define-record unbound，说明构建把 rivet 库里的同名 API 当成了依赖——检查 rivet.rktd 与 import 路径，勿再去切旧分支（RIVET-LIB-BACKLOG P1）

## 参考文档

- `docs/RIVET-MIGRATION.md` — 架构决策、里程碑 M0-M7、验收门禁
- `docs/RIVET-LIB-BACKLOG.md` — Rivet 库改进清单（Taskly 驱动发现的）
- `shared/spec/PRODUCT-SPEC.md` — 产品行为契约（UI 必须对齐这个）
- `shared/spec/CLI-SPEC.md` — CLI 契约（M6 用）
- Windows 端已实现同款功能的 C# 参考：git 历史 `main` 分支的 `apps/windows/Taskly/`
