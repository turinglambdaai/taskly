# Taskly × 优秀任务管理器设计借鉴

> 对标对象：Things 3（Cultured Code，Apple Design Award）与 2Do（Beehive）。
> 目的：把经过市场验证的交互设计吸收进 Taskly 的跨平台契约——先模仿其"信息
> 架构与交互语法"，不抄视觉皮肤；一切借鉴以 PRODUCT-SPEC 契约形式落地，三平台
> 同步。
>
> 状态标注：✅ 已落地（experiment 分支）· 🔜 短期可做（宿主层，无 schema 变更）
> · 🧱 需要 schema v5（迁移成本大，需单独立项）· ❌ 不采纳（附理由）。

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

- ✅ 已落地（Linux 宿主）：Ctrl+1…4 切视图、Ctrl+N 聚焦快速添加、Ctrl+F 聚焦
  搜索、Ctrl+Shift+C 切换显示已完成（PRODUCT-SPEC §8 的加速器全量接线）；
  Esc 阶梯（编辑器 → 搜索 → 放行）。
- 🔜 短期：↑/↓ 在任务列表内的行导航 + Enter 展开/收起编辑器。GTK 的焦点链
  已支持一部分，需要把行激活语义接上。

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

- 🔜 短期：任务行多选（Ctrl/Shift 点击）+ 批量完成/移动/删除。宿主层实现，
  但 PRODUCT-SPEC 需先定义批量语义（哪些字段可批改、撤销粒度）。

### 2.5 Quick Find

✅ 已有对应物：头部搜索框 + 后端 search_tasks（跨清单模糊搜索）。

## 3. 明确不采纳的

- **2Do 的位置提醒（Nearby）**：需要移动端定位能力，桌面端价值低。
- **Things 的 Areas（领域）**：引入"项目→任务"两级层级，违背 Taskly
  "轻清单"定位；如果未来要做，走 Lists→Group 一层分组即可，不复制 Area。
- **2Do 的日历集成（CalDAV 双向同步）**：与"一个 SQLite 文件 + 云盘同步"
  的产品路线冲突，保持文件即数据库的简单性。
- **跨平台协作/分享**：两者都不擅长、Taskly 也不做（单机 + 云盘文件同步）。

## 4. 落地顺序建议

1. 🔜 纯宿主层（无契约变更）：↑↓ 行导航与 Enter/Esc 编辑流、搜索命中高亮、
   空状态插画化。
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
