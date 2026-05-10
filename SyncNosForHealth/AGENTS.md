# SyncNosForHealth（iOS）开发约定

> 作用域：`SyncNosForHealth/**`

## Apple App 开发规范（Swift/SwiftUI 基线）

> 本节为项目内复制版基线规范。后续如需更新，以本文件为准。

### 核心技术栈

- 架构模式：MVVM (Model-View-ViewModel)
- 编程范式：Protocol-Oriented Programming（面向协议）
- UI：SwiftUI（按需）
- 状态管理：Observation（`@Observable` / `@Bindable`）；必要时使用 Swift Concurrency；仅在需要 Publisher 管道时引入 Combine
- 持久化：SwiftData（按需）
- Swift：Swift 6.0+

平台支持（按项目选择）：
- iOS 17.0+、iPadOS 17.0+、macOS 14.0+、visionOS 2.0+

### 设计原则

- 组合优于继承：优先依赖注入
- 接口优于单例：利于测试与替换
- 显式优于隐式：数据流与依赖清晰可追踪
- 协议驱动：优先“新增实现”而不是“改 switch”

工程简洁性：
- KISS：能简单就别复杂
- YAGNI：不为不确定未来预埋
- DRY + WET：避免重复，但别过早抽象（通常重复 2–3 次后再抽）

### MVVM 架构规范

职责划分：
- **Model**：纯数据结构；不放 UI 逻辑（避免引用 SwiftUI/Observation/Combine）
- **ViewModel**：业务流程编排、状态管理、数据转换；不直接做 UI 操作；避免隐藏单例依赖
- **View**：渲染与交互绑定；不写业务逻辑；不直接访问数据库/网络
- **Service/Repository**：网络、持久化、文件 IO 等副作用；优先协议抽象 + 注入

模块化建议（可选，不是硬性要求）：
- 逻辑层可下沉到 SwiftPM，以便测试与复用
- 建议依赖方向保持单向：`SwiftUI 层 → ViewModel → Services → Models`
- 建议拆分：`Models` target（纯数据结构）与 `Services` target（业务逻辑与基础设施）

ViewModel 规范（Observation 优先）：
- iOS 17+ / macOS 14+：优先 `@Observable` / `@Bindable`
- 避免单例：不要用 `static let shared`
- 依赖注入优先：初始化参数或 `.environment(...)`
- 不使用 `ObservableObject` / `@Published` / `@StateObject` / `@ObservedObject` / `@EnvironmentObject`（统一用 Observation 体系）

SwiftUI 事件处理：
- 优先使用 `.onChange(of:) {}` 的无参数重载
- 只有确实需要 `oldValue` / `newValue` 时，才使用带两个参数的重载

协议驱动开发：
1. 先定义协议，再实现类型
2. 用协议消除类型分支（减少 `switch` 的维护成本）
3. 新增能力优先“增加实现”而不是“修改中心分发器”

测试与调试：
- build/test/run 统一使用原生 `xcodebuild`
- 单元测试优先级建议：逻辑层 / ViewModel / UI 层统一用 XCTest（通过 `xcodebuild test` 跑）
- 日志用 `os.Logger`，明确 `subsystem` 与 `category`

## SyncNosForHealth（iOS）核心目标（V1）

- 读取 HealthKit 睡眠数据（timeline 区间事件）并在 App 内渲染。
- 用户选择某一天 → 手动同步到 Notion（幂等 upsert；V1 只写 `Date(title)` + `TotalSleepMin(number)`）。
- Notion OAuth 复用既有基础设施（GitHub Pages 回调 + Cloudflare exchange）。

## SyncNosForHealth（iOS）硬性规则

- **不引入 macOS 绑定**：不得直接依赖 `SyncNos/` 主工程中的 `NSApplication`、macOS-only 逻辑或历史 DI 体系。
- **不在 UserDefaults 存 token**：Notion `access_token` 必须写入 **Keychain**；UserDefaults 仅存非敏感配置（开关、parentPageId、db override 等）。
- **主线程禁做网络/重计算**：网络请求、HealthKit 查询、Notion 写入必须在后台任务中完成；UI 更新回到主线程。

## 目录建议（可按需调整）

- `SyncNosForHealth/Settings/**`：设置页 UI + ViewModel + 配置持久化（非敏感）
- `SyncNosForHealth/Notion/**`：iOS 专用 Notion client / OAuth / Keychain store
- `SyncNosForHealth/HealthKit/**`：授权与睡眠 timeline 查询
- `SyncNosForHealth/SleepUI/**`：睡眠图表与按天查看 UI

## 验证与提交

- 运行命令一律使用 `rtk` 前缀，例如：
  - `rtk xcodebuild -project SyncNos.xcodeproj -scheme SyncNosForHealth -sdk iphonesimulator build`
- 一个 task 一次原子 commit；不要 push。
- `.github/features/**` 下的计划文件默认不提交到 git（除非你明确要求入库）。

