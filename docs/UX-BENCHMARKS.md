# Taskly × 优秀任务管理器设计借鉴

> 对标对象：Things 3（Cultured Code，Apple Design Award）与 2Do（Beehive）。
> 目的：把经过市场验证的交互设计吸收进 Taskly 的跨平台契约——先模仿其"信息
> 架构与交互语法"，不抄视觉皮肤；一切借鉴以 PRODUCT-SPEC 契约形式落地，三平台
> 同步。
>
> 状态标注：✅ 已落地（main，平台覆盖见标注）· 🔜 短期可做（宿主层，无 schema
> 变更）· 🧱 需要 schema v5（迁移成本大，需单独立项）· ❌ 不采纳（附理由）。

## 1. Things 3 的可借鉴设计

### 1.1 时间四层架构（Today / Upcoming / Anytime / Someday）

Things 的灵魂是把"什么时候做"压进四个默认视图，用 **start date（何时进入视
野）与 deadline（何时必须完成）分离**控制任务流入注意力的节奏。

- Taskly 现状：Today / Planned / All / Completed 四视图 + 自然语言 due date。
  没有 start date 与 deadline 的区分，Planned 是平面日期列表。
- 🔜 提案（跨平台一致后再做）：Planned 视图按 **逾期 / 今天 / 明天 / 本周 /
  以后** 分节渲染（Things Upcoming 的分组阅读体验）。先在 Linux 宿主做了
  原型，但 macOS/Windows 尚无此分组——按「一致性优先」回退为提案，待
  PRODUCT-SPEC 收录后三平台同步。
- 🧱 值得立项：`start_date` 列（任务何时"出现"在今天/计划里，与 due 分离）。
  这是 Things 体验的核心机制，也是 2Do「Start Date」的同款能力。需要 schema
  v5 + 三平台迁移 + CLI/视图语义扩展。
- 🧱 值得立项：deadline（硬截止）与 due（计划完成）分离，逾期表现不同。

### 1.2 键盘优先（keyboard-first）

Things 几乎一切操作无需鼠标：全局快速录入、⌘N 新任务、⌘F 搜索、↑↓ 遍历、
⌘1…4 切视图、Enter 展开、Esc 收起。

- ✅ 已落地（三平台）：Ctrl+1…4 切视图、Ctrl+N 聚焦快速添加、Ctrl+F 聚焦
  搜索、Ctrl+Shift+C 切换显示已完成——Linux 宿主全量接线并带 Esc 阶梯
  （编辑器 → 搜索 → 放行）；macOS 同一组命令走 ⌘ 系快捷键（⌘1…4/⌘N/
  ⌘F/⇧⌘C）；Windows 用 KeyboardAccelerator 全窗口挂载同一契约，菜单上
  另标 Ctrl+Shift+N / Ctrl+O 数据库快捷键提示。
- ✅ Linux 任务列表：GTK 原生多选支持 Ctrl/Shift 点选和方向键焦点移动；
  Enter（或双击）激活选中行的行内编辑，Esc 先关闭编辑、再清除任务选择。
  任务列表轮询重建时按任务 ID 恢复选中状态。
- ✅ 批量移动/完成/删除与跨视图选中策略已在三平台落地（详见 §2.4）。

### 1.3 "安静"的哲学（quiet software)

获 Apple Design Award 的核心不是功能多，而是**默认界面只有今天该做的事**，
其他一切按需出现。Taskly 已有的对应物：智能视图 + 空状态（📂/✓）+ 完成即
沉底。借鉴结论：**拒绝功能堆砌，任何新能力先进 spec 评审是否"默认可见"**。

### 1.4 Logbook（已完成日志）

✅ 已有对应物：Completed 视图即 Logbook 的轻量版。

## 2. 2Do 的可借鉴设计

### 2.1 Focus Lists（Starred / Scheduled）

2Do 用"聚焦清单"把跨清单的关注点提为一级视图：Starred（星标优先）、
Scheduled（有日期的）。

- 🧱 值得立项：`starred` 列（0/1）+ Today 旁的 ⭐ 智能视图。轻 schema 变更
  （一列），可与 start_date 同一次 v5 迁移打包。

### 2.2 重复任务（Recurring）

2Do 的强项：灵活重复规则（日/周/月/年、间隔、按完成日调度）。

- 🧱 值得立项：`recurrence` 列（规则字符串）+ 完成时派生下一次的调度逻辑。
  派生逻辑必须放 Racket 核心（一份实现），宿主只展示。schema v5 打包。

### 2.3 多重提醒与持续催办

2Do 允许单任务多条提醒，"nag you till it's done"。

- ✅ 部分落地：Linux 宿主已实现 PRODUCT-SPEC §9 的到期通知调度（60s 轮询 +
  启动检查 + 去重 + ≤3 逐条/>3 汇总 + 永不崩溃）。
- 🔜 短期：到期通知的"稍后提醒"动作（需要 rivet 通知适配器扩展 action 回调）。

### 2.4 批量编辑（Batch Edit）

2Do 支持多选后批量改日期/清单/删除。

- ✅ macOS 已落地：⌘/⇧ 多选 + 批量完成/排期/移动/删除；删除与另两端
  相同，先隐藏并延后六秒提交，撤销恢复原 ID 与全部元数据。
- ✅ Windows 列表选择与行内详情：WinUI Extended 模式支持 Ctrl/Shift
  多选、方向键与范围选择；Enter、双击或 ⓘ 在当前行展开标题、备注、日期与时间，
  不再调用 PromptAsync。Enter 保存、Esc 取消；切换行时保存。按任务 ID 在列表刷新后
  恢复选择与编辑草稿（普通列表与搜索结果）。
- ✅ Windows 批量操作（分阶段）：选择多条任务时显示共享操作栏；
  支持一次批量标记完成、批量移动到目标列表；使用稳定任务 ID，列表刷新
  与搜索不会把操作错误应用到其他任务。打包验收覆盖两条任务批量完成。
- ✅ Windows 批量排期：多选时支持今天、明天、清除三种日期操作；
  清除日期同时清除时间，避免任务残留不可见的 due_time。
- ✅ Linux：基于 GTK 原生多选（#33）增加可见的批量完成和批量移动操作栏，
  同时适用于当前列表和全局搜索。刷新时按任务 ID 保留选择。
- ✅ Windows 单条/批量删除采用 6 秒延后提交：先隐藏选中任务，期间撤销可直接恢复原任务 ID 与元数据，超时才发送后端删除 RPC；失败时恢复任务。
- ✅ Linux 批量排期：多选状态下可设置今天、明天或清除日期；
  清除日期同时清除 due_time，操作按任务 ID 捕获并重新查找真实任务。
- ✅ Linux 单条/批量删除：6 秒可撤销窗口内仅隐藏对应任务 ID；
  过期或主动关闭后才提交后端删除。撤销不创建新任务，保留原任务 ID
  与完整元数据；数据库切换时不会把旧任务 ID 用于新库。
- ✅ 三平台打包原生 UI 验收记录行内编辑/Escape 焦点流；Windows/macOS
  另验证 Enter 提交与完整行内草稿，三端均验证稳定 ID 删除撤销。

### 2.5 任务编辑与日期提交（2026-10-28 复核）

这次复核只借鉴可解释的交互原则，不复制平台外观：

- **Things**：Return 打开编辑，Command-Return 明确保存并关闭；When 选择器把
  Today 等快捷项、日历和 Clear 放在同一个日期入口中。Taskly 采用“日期入口
  内先快捷日期、再原生日历”的层级，但保留跨平台可见 Save/Cancel，避免只靠
  macOS 隐式收起行为。
- **Apple Reminders**：任务行的详情入口可发现，Add Date 先给建议日期，Custom
  再进入日历；日期与可选时间是相邻但独立的字段。Taskly 延续 ⓘ 行内展开，
  日期清除同时清除不可见时间，避免悬空排程。
- **TickTick**：创建时的日历图标和详情页的 Date & Reminder 都把排程作为明确
  入口。Taskly 不复制其完整详情页，而把日期、时间、列表保留在轻量行内草稿。

Taskly 自己的事务边界是：标题、备注、日期、时间、列表属于同一草稿；选择日期
只更新草稿；可见 Save、Return 或点击离开才持久化；Cancel/Escape 整体丢弃；
保存先显示进行中，再显示成功或错误，显式保存失败时保留完整草稿。三端使用
SwiftUI DatePicker、WinUI CalendarView、GTK Calendar 等各自原生控件，不追求
像素一致。完整场景与验收责任归 `shared/spec/PRODUCT-SPEC.md` §5b/§6/§7。

官方依据：

- Things Scheduling / Keyboard Shortcuts：
  https://culturedcode.com/things/support/articles/2803579/
  https://culturedcode.com/things/support/articles/2785159/
- Apple Reminders, Add or change reminders on Mac：
  https://support.apple.com/guide/reminders/add-or-change-reminders-remndc729e28/mac
- TickTick, Add Tasks / Effective Reminder Feature：
  https://help.ticktick.com/articles/7055782422935240704
  https://help.ticktick.com/articles/7055782395743567872

### 2.6 Quick Find

✅ 已有对应物：头部搜索框 + 后端 search_tasks（跨清单模糊搜索）。

## 3. 明确不采纳的

- **2Do 的位置提醒（Nearby）**：需要移动端定位能力，桌面端价值低。
- **Things 的 Areas（领域）**：引入"项目→任务"两级层级，违背 Taskly
  "轻清单"定位；如果未来要做，走 Lists→Group 一层分组即可，不复制 Area。
- **2Do 的日历集成（CalDAV 双向同步）**：与"一个 SQLite 文件 + 云盘同步"
  的产品路线冲突，保持文件即数据库的简单性。
- **跨平台协作/分享**：两者都不擅长、Taskly 也不做（单机 + 云盘文件同步）。

## 4. 落地顺序建议

1. 🔜 纯宿主层（无契约变更）：搜索命中高亮、空状态插画化。
2. 🧱 schema v5 一次迁移打包：`starred` + `start_date` + `recurrence`
   （+ 视为候选的 deadline 分离）。DATA-FORMAT bump、三平台迁移链、CLI-SPEC
   扩展、同一 release 发三平台——需要单独立项评审。
3. 持续：每个借鉴点先进 `shared/spec/PRODUCT-SPEC.md`，再进实现；宿主不做
   spec 之外的自嗨功能。

## 参考

- Things 3 官方：默认视图与调度
  https://culturedcode.com/things/support/articles/4001304
  https://culturedcode.com/things/support/articles/2803579
- Things 3 评测与设计分析：
  https://independent-app-reviews.org/reviews/things-3-review
  https://digitoolbook.com/en/blog/things3-minimalist-task-management-gtd
- 2Do 官方功能页：https://www.2doapp.com/page-section/main-features
- 2Do Focus Lists：https://www.2doapp.com/docs/ios/focus-lists

### Windows task ownership recovery

- ✅ Task rows expose a right-click **Move to List / 移动到列表** submenu for
  other lists. It calls `update_task` with the target list ID, preserving
  title, due date/time, completion state and notes.
- This is the **explicit** recovery path for tasks already saved into the
  wrong list by older Windows versions. Do not auto-migrate existing rows:
  the original intended list cannot be inferred reliably.
- Manual acceptance: move a task from 工作 to 生活, confirm it disappears from
  工作, appears in 生活 and keeps all other fields; then restart and verify
  ownership persists. Exercise both languages and all smart-list views.

## Raycast 对照（商业标杆，2026-10-23 实拆 2.9.0.0）

> 对象：Raycast（macOS 启动器，收费商业软件）。实拆官方 DMG：Info.plist、
> 自研更新器（Updater/UpdaterDaemon，无 Sparkle）、IPC 面、Settings 前端
> 包、InternetAccessPolicy.plist，对照 manual.raycast.com。结论按
> 「学 / 参考 / 不学」记录，落地见 PRODUCT-SPEC §8 与对应切片。

### 学到的（已落地或已排期）

- **About = 更新/链接/反馈门户**：Raycast 的 Settings → About 收口
  Raycast Updates、Open Changelog、Website、社区、Send Feedback 五个入口。
  Taskly 采纳：About 增加 User Manual 与 Changelog 链接（Website/Report an
  Issue 已有），构成「更新（菜单）+ 手册 + 日志 + 反馈」门户。
- **复制诊断信息**：Raycast IPC 有 CopyLogFiles。Taskly 采纳：About 增加
  诊断块（版本/平台/架构/OS/DB 路径/配置路径，英文固定标签，可选中）+
  「复制诊断信息」按钮，粘贴进 issue 即可带全上下文。
- **网络透明度**：Raycast 随包分发 InternetAccessPolicy.plist，按主机声明
  用途与拒绝后果（Little Snitch 等防火墙直接呈现给用户）。Taskly 采纳为
  安装链切片：声明 github.com 更新源——把「本地优先、只连更新源」的信任
  故事写进包里。
- **更新行为显性化**：Raycast 把更新入口明示在 About。Taskly 排期：设置页
  增加「自动检查更新」开关（默认开，写 config），把已有的 4h 静默检查
  显性化；下载后仍确认再装（与 Raycast 的退出静默安装分叉——任务管理器
  是数据工具，保留用户控制感）。
- **手册结构**：manual.raycast.com 的 Keyboard Shortcuts / Import &
  Export / Troubleshooting 独立成章、changelog 挂首页。Taskly 排期并入
  手册切片：快捷键全表（§8 面向用户版）与「数据在哪/如何备份」章节。

### 参考但不照搬

- 退出时静默自动安装（CanShutDownForAutoInstall）：不采纳，理由同上。
- Sentry 崩溃上报内置于包：v1 无遥测、crash 仅 opt-in，按自己的清单走。
- 社区/Slack 入口：单机 + 云盘同步路线，GitHub issues 即反馈渠道。
- 更新后一次性亮点提示（changelog 一等公民）：条件比 Raycast 更好
  （结构化 CHANGELOG 自动进 release），列为后续增量切片。

### 明确不学

账号/Store/云同步/AI（与本地优先正面冲突）；纯英文零本地化（双语是
Taskly 契约优势）；设置页做 WebKit 壳（宿主原生 + i18n 单源）；macOS 26
最低版本门槛（14+ 是真实覆盖面差异）。
