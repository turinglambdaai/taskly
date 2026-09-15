# AGENTS.md

指引给 AI agent（及开发者）：如何理解、构建、运行、改动 Taskly。

## 这是什么

Taskly 是**原生**待办应用套件（monorepo）。同一产品在三个桌面平台各用第一方 UI 技术栈实现，**不共享任何运行时代码**，靠 `shared/spec/` 下的契约保持一致：

| 平台 | 技术栈 | 目录 | 验证状态 |
|---|---|---|---|
| macOS 14+ | Swift 6 + SwiftUI（零第三方依赖，SQLite3 用系统库） | `apps/macos/` | ✅ 构建+测试+CLI 冒烟已验证 |
| Windows 10+ | WinUI 3 (Windows App SDK) + .NET 10 | `apps/windows/` | 源码完成，需 Windows/CI 构建验证 |
| Linux | Vala + GTK4/libadwaita（GNOME 第一方语言，编译为 C/GObject） | `apps/linux/` | ✅ 原生构建+契约测试已验证 |

每个二进制都是双模式：**无参数启动 GUI；带任何参数走 CLI**（GUI 框架完全不初始化，可无头运行）。

旧版 Avalonia 实现（0.6.x）冻结在 `src/Taskly/` 作为行为参照，原生 1.0 GA 后删除。架构决策记录：`ARCHITECTURE.md`。

## 快速命令

```bash
# macOS（Swift Package）
cd apps/macos && swift build && swift test     # 24 个契约测试
.build/debug/Taskly list --json
.build/debug/Taskly add "买牛奶" --due tomorrow --json
scripts/make-app.sh                             # 打包 Taskly.app

# Windows（WinUI 3，只能在 Windows 上构建）
dotnet build apps/windows/Taskly/Taskly.csproj -c Release

# Linux（Vala → C → 原生二进制）
cd apps/linux && meson setup build && meson compile -C build && meson test -C build

# i18n 单源同步与校验
scripts/sync-i18n.sh            # shared/i18n → 各平台资源目录
scripts/sync-i18n.sh --check    # CI 模式：仅校验
```

## 契约文档（改任何行为前必读，改动必须同步契约）

| 文档 | 内容 |
|---|---|
| `shared/spec/DATA-FORMAT.md` | SQLite schema v4、列↔字段映射、日期存储格式（`yyyy-MM-dd`/`HH:mm`/ISO-8601 本地时区）、WAL、`~/.taskly/config.ini`、默认「工作」列表（color = -4104388） |
| `shared/spec/CLI-SPEC.md` | 子命令、`--json` 字段名与顺序、退出码 0/1/2/3/4、`--due` 语法全集（`+Nm/+Nh/+Nd/+Nw/+NM`、`@now/@10am/@22:30 + tomorrow/tmw/星期`、裸词 today/tomorrow/tmw/tonight、绝对日期四格式）、纯日期意图清除时间规则 |
| `shared/spec/PRODUCT-SPEC.md` | 视图/过滤/排序、任务行与详情对话框交互、提醒调度（60s 轮询+启动检查+去重+≤3逐条/>3汇总）、验证上限（1000/100/200/年份 1900–2100） |
| `shared/spec/DESIGN-TOKENS.md` | 暖色板（Pampas #F4F3EE + Crail #C15F3C，明暗两套）、10 色 iOS 调色板、6×8 emoji 分类 |
| `shared/i18n/{zh,en}.json` | 全部用户可见文案（约 98 键），平台副本必须逐字节一致 |

## 改动契约（不要破坏）

- **DB schema**：`user_version = 4`。加列必须 bump 版本 + 三平台迁移链同步落地 + 更新 DATA-FORMAT.md，同一 release 发三平台
- **CLI JSON 字段与退出码**：task 对象 `id, listId, listName, text, completed, dueDate, dueTime, notes, createdAt`（null 省略、2 空格缩进、非 ASCII `\uXXXX` 转义）；错误走 stderr `{"ok":false,"error":…,"exitCode":N}`
- **默认数据**：新库种下名为 `工作`（硬编码中文）的列表，icon `📋`，color ARGB int（有符号）
- **通知永不崩溃**：权限拒绝/传输失败 → 本会话禁用通知（0.6.1 macOS 崩溃事故是永久回归测试）
- **`~/.taskly/` 路径约定**：GUI/CLI/云盘同步都依赖它

## 项目结构

```
taskly/
├── apps/
│   ├── macos/          Swift 包：Sources/{Models,Data,Repositories,Services,Themes,Views,ViewModels,Cli} + Tests + scripts/make-app.sh
│   ├── windows/        WinUI 3：Views/Dialogs/XAML + Cli/Data/Models/Services（C# 核心层移植自旧版）
│   └── linux/          Vala/GTK4：src/*.vala + tests/ + meson.build + flatpak/
├── shared/
│   ├── spec/           四份契约文档（canonical）
│   ├── i18n/           zh.json / en.json 单源
│   └── assets/         图标源文件
├── scripts/            sync-i18n.sh 等
├── src/Taskly/         旧版 Avalonia（冻结）
├── .github/workflows/  ci.yml（旧版构建）· native.yml（三平台原生 CI）
├── ARCHITECTURE.md     架构决策记录
├── COMMERCIAL-CHECKLIST.md   商业化工程清单（签名/许可证/收费钩子/发布）
└── docs/               GitHub Pages 官网
```

## 常见任务指引

- **改共享行为**（视图过滤、CLI 语义、文案）：先改 `shared/spec/` 或 `shared/i18n/`，再逐平台落地，跑 `scripts/sync-i18n.sh`，最后各平台测试
- **macOS 加功能**：`apps/macos/Sources/Taskly/`，MVVM 模式（AppState @Observable + SwiftUI 视图）；改完 `swift test` 必须绿
- **加 CLI 子命令**：三平台各自实现（macos `Cli/CliEngine.swift`、windows `Cli/CliEngine.cs`、linux `src/cli.rs`），保持 JSON/退出码一致，并在 CLI-SPEC.md 补文档
- **加 DB 列**：见 DATA-FORMAT.md §5 迁移规则，三平台迁移链逐字同步
- **改配色/令牌**：先改 `shared/spec/DESIGN-TOKENS.md`，再改 macos `Themes/Palette.swift`、windows `App.xaml` 主题字典、linux `ui.vala` APP_CSS
