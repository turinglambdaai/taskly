# Taskly on MacBook Pro — 开发交接 / Handoff

> 写给要在 MacBook 上继续 Taskly×Rivet 开发的人（或 AI 会话）。
> 一切都已推送；这里是可以直接照做的步骤和当前状态的完整地图。

## 仓库与分支

| 仓库 | 分支 | 用途 |
|---|---|---|
| `turinglambdaai/taskly` | `experiment/taskly-rivet`（开发主线） | Rivet 项目布局：`rivet.rktd` + `racket/taskly/`（Racket 领域核心，M0 ✅）+ `app/backend.rkt`（Rivet 后端入口）+ `windows/`（C++/WinRT 宿主）+ `macos-host/`（SwiftUI 宿主脚手架） |
| `turinglambdaai/rivet` | `main` | ⚠️ 旧交接里说的 `recovered/taskly-m1` 分支已从远端消失（2026-10-01 核实）；named-record 层当前唯一存活的实现在本仓库 `racket/taskly/rivet-schema.rkt`，向上游移植已立 issue：turinglambdaai/rivet#92（进度见 RIVET-LIB-BACKLOG 状态表） |

`main`（taskly）= 删除前的原生三平台实现，仅作历史安全网；Rivet 分支才是主线。

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
- Windows：C# WinUI 版已按「不破不立」删除（git 历史保留）；C++/WinRT 宿主骨架在 `windows/`（M3 重集成待做：vcxproj 需适配当前 rivet 的构建契约——见下方「已知坑」）

### macOS 端任务（你的 MacBook 上的工作顺序）

1. **跑通 hello 宿主**：`raco rivet build && raco rivet dev`——验证当前 rivet 的 macOS 宿主在本机可构建可启动（9/21 的崩溃发生在 Windows；macOS 宿主 + 当前 rivet 很可能直接通过）
2. **接 Taskly 后端**：`rivet.rktd` 的 backend 已指向 `racket/taskly/backend.rkt`（真实 Taskly 领域层，非 hello）。`raco rivet dev` 应启动一个带真实 SQLite 数据的 SwiftUI 窗口
3. **移植 Taskly SwiftUI UI**：旧原生实现的完整 UI 在 git 历史（`git show main:apps/macos/Sources/Taskly/Views/MainWindowView.swift` 等）——Reminders 式布局、chips、主题系统都在里面。`macos-host/Sources/RivetHost/ContentView.swift` 是移植目标；数据源从 SQLite 直连改为 GeneratedBackend.swift 的类型化客户端（backend.rkt 的 RPC 面：open_database/load_snapshot/add_task/update_task/...）
4. **给 rivet 提 PR（第一个）**：把 named-record API（define-record/Optional/嵌套记录）从本仓库 `racket/taskly/rivet-schema.rkt` 移植进 rivet main——这是 taskly Racket 核心对 rivet main 的唯一硬依赖（backlog P1；原 `recovered/taskly-m1` 分支已从远端消失，勿再寻找）
5. **M6**：把 agent-facing CLI（原 C# CliEngine，CLI-SPEC 契约）用 Racket 重写（领域层已在 Racket，很薄）

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
