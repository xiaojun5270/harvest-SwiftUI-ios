# Harvest Native for iOS

This directory contains the native SwiftUI edition of Harvest. It is independent
from Flutter and CocoaPods and targets iOS 17 or later.

Open `Harvest.xcodeproj` with Xcode 26 or later, choose a development team, and
run the `Harvest` scheme. The backend API is shared with the Flutter client.

The native target keeps the production bundle identifier `com.ptools.harvest`
and uses version `2026.1011.01` with build `298`, so it can be signed as the next
update of the existing iOS app. Do not install a Flutter and native archive with
the same bundle identifier side by side.

## 代码更新记录

后续每次代码修改完成后均同步更新此处，无论是否调整版本号。同一发布版本的
改动持续追加到对应版本下，并按时间倒序排列；内容说明本次具体新增、修改、
优化或修复了什么，不堆叠提交哈希和无意义的内部日志。

### 2026.1011.01 (298) - 2026-10-11

- 对照 Flutter `afd4be55...3559697e` 完成增量审查：Flutter 新增的
  GoRouter 单实例、Overlay 定位和 dispose 期间 Provider 延迟更新均属于 Flutter
  渲染/路由实现，原生 SwiftUI 没有对应代码路径，无需复制；原生功能和接口保持不变。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展的版本统一同步至
  `2026.1011.01 (298)`。

### 2026.1009.01 (297) - 2026-10-09

- 对照 Flutter `96268b5e...afd4be55` 完成增量同步：新增豆瓣“正在热映”接口
  `/api/option/douban/now_playing`，在豆瓣资讯首位展示并复用现有并发加载、
  会话缓存、下拉刷新和详情页；同步解析嵌套封面、评分、副标题及“可播”状态。
- 复核 Flutter 全局 Material 依赖清理、组件兼容层和 Web 专用 SSE fetch 分流；
  原生 SwiftUI 已使用原生组件与 URLSession 流式搜索，不复制 Flutter/Web 实现。
- TG Bot 签到配置支持维护多条有序命令，执行时逐条发送并分别等待回复；旧版
  单命令配置继续兼容，卡片与执行历史会显示完整命令链。
- TG Bot 签到支持交互面板：收到普通回复键盘时发送匹配按钮文字，收到内联
  键盘时提交 callback payload，并继续等待 Bot 最终结果；按钮关键词可配置，
  默认自动匹配“签到”，需要密码、网页或额外资料的按钮会明确提示而不会误点。
- TG Bot 重试调整为单命令粒度，已经成功的命令不会因后续命令超时而重复发送；
  内置识别“签到成功、今日已签到、已经签到”等结果并立即锁定成功状态。成功
  记录自动通过后端现有通知接口转发到已配置的企业微信通道，转发失败仅写入
  App 日志，不会把已经完成的 Telegram 签到改判为失败。
- TG 签到统计改为展示在各 Bot 独立卡片内，每张卡片紧凑显示执行、成功、
  失败（含超时）和成功率，不再占用页面顶部空间。计数独立于 300 条执行历史
  上限，旧快照首次加载时会由现有历史自动回填。
- TG Bot 新增自动识别列表：读取已登录 Telegram 的主聊天和归档聊天，只筛选
  真实私聊 Bot，支持搜索、多选和批量添加；已配置 Bot 自动标记并跳过，新增项
  同时缓存聊天 ID，保留手动添加入口作为补充。
- TG 定时签到设置移入任务中心的“TG 签到”分段，统一管理启用状态、执行时间、
  星期和命令预览；站点页 TG 列表下拉刷新现在只刷新 Bot 聊天元数据，不会触发
  批量签到或发送 Telegram 命令。
- TG 调度器接入 App 生命周期与 iOS `BGAppRefreshTask`：前台恢复时立即检查，
  进入后台时提交下一次系统唤醒请求，不再要求用户先打开站点页或任务中心；后台
  是否实际唤醒仍由 iOS 系统策略决定，不能保证固定时间执行。
- TG 会话改为按需初始化：App 启动和普通前后台切换不再创建 TDLib；只有打开
  TG 页面/任务中心或系统实际唤醒后台任务时才启动，页面离开后停止前台轮询。
  未配置启用定时 Bot 时不会提交后台刷新请求，降低常驻内存和电量消耗。
- 修复接入 TDLibKit 后其 `Date` 模型与 Foundation 日期类型同名导致的 Swift
  编译失败；Telegram 签到配置、执行记录、回复匹配与定时设置统一显式使用
  `Foundation.Date`，恢复无证书 IPA 构建。
- 修复 TG Bot 编辑页带标题和页脚的 SwiftUI `Section` 初始化方式不兼容造成的
  泛型推断失败，结果判断与定时签到分组改用显式标题和页脚构造。
- 新增完全运行在 iOS 本机的 Telegram Bot 签到模块，不改 Harvest 后端：站点页
  增加“站点 / TG 签到”分段，支持添加、编辑、停用、删除 Bot，手动或批量发送
  签到命令，并按成功/失败关键词判断回复、记录耗时与完整执行历史。
- 接入官方 TDLib 的 Swift 封装 TDLibKit，以 Telegram 用户账号向第三方 Bot 发消息；
  补齐 API ID/API Hash、手机号、验证码和两步验证登录流程，凭据与数据库加密密钥
  存入钥匙串，TDLib 会话数据库持久化并排除 iCloud/设备备份。
- TG Bot 支持按星期和时间前台定时签到、回复超时与有限重试、Bot 会话 ID 缓存、
  Telegram 外部跳转和操作反馈；明确 iOS 挂起或终止 App 后不保证定时任务执行。

### 2026.0930.01 (296) - 2026-09-30

- 修正下载器实时数据解析：活跃数、暂停数和总数只读取实时响应的标准字段，
  qB/TR 会话流量按各自数据结构读取，真实的 0 值可覆盖旧缓存，避免卡片与
  下载器内部统计不一致；HTTP 汇总兜底不再覆盖较新的 WebSocket 实时数据。
- 站点列表上下滑动时立即收起搜索键盘，避免键盘持续遮挡下方站点卡片。
- 站点编辑页读取站点配置中的全部镜像 URL，支持从菜单切换多个镜像地址，
  同时保留自定义地址输入；编辑已有站点时也会加载对应配置与镜像候选。
- 下载器卡片补齐地址与种子路径连接区，并保留连接、启用、辅种、实时速度、
  活跃数、总数、剩余空间和限速状态展示，使信息结构与 Flutter 一致。
- 下载器菜单拆分为参数设置、限速设置、连接检查、分类管理和标签管理；分类
  与标签分别使用独立大尺寸 sheet，限速入口直接打开对应设置分组。
- 下载器基础编辑页隐藏 Flutter 未展示的排序字段，但保存时继续保留原排序值；
  高级设置移除内部 API 键名提示，统一使用中文字段名称。
- 复核 Flutter 安卓真机下载器菜单修复：问题源于等待 shadcn Overlay 关闭
  Future 不返回；原生 SwiftUI 菜单直接更新编辑与工具 sheet 状态，不存在
  该阻塞链路，无需复制 Android/Flutter 专属修复。
- 复核 Flutter 依赖锁文件与 Android AGP/Kotlin 构建链升级；原生工程不使用
  Flutter、Gradle 或相关依赖，本轮没有 API、数据模型和功能代码变化。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展的版本统一同步至
  `2026.0930.01 (296)`。

### 2026.0928.01 (295) - 2026-09-28

- 资源搜索结果按标题与副标题的中日韩字符数量自动选择主标题，中文更多的
  文本优先加粗显示，另一条固定作为弱化副标题。
- 搜索设置新增站点筛选框，支持按站点名称、代码、昵称及镜像、RSS、种子页
  域名筛选；筛选仅影响当前展示，全选、随机和保存仍作用于完整站点集合。
- 新增、编辑下载器以及分类、标签、工具管理在移动端固定使用大尺寸 sheet，
  并显示拖动指示器，避免管理表单空间不足或无法完整操作。
- 复核下载器编辑、参数设置、选择下载器与暗黑模式样式；原生 SwiftUI 已使用
  系统表单、主题前景色和原生 sheet，无需引入 Flutter Material/shadcn 重构代码。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展的版本统一同步至
  `2026.0928.01 (295)`。

### 2026.0918.01 (294) - 2026-09-18

- 修复消息历史与消息详情标题在深色模式下可能继承错误颜色的问题。
- 重新设计消息列表卡片、结构化预览和消息详情；任务与今日数据消息统一采用
  执行详情的两列指标和可展开明细布局，避免大量记录一次性铺满页面。
- 消息缓存补齐正文内容，离线或后台刷新期间仍可查看完整预览和详情。
- 主导航品牌图标改为放大圆形裁切，使图标内容填满 Liquid Glass 圆形入口。
- 复核 iOS 27 Scene 生命周期和角标同步：原生端已使用 SwiftUI `WindowGroup`
  与系统通知角标 API，前台恢复时会重新同步通知，无需引入 Flutter 专属代理。
- 复核移动端站点长按菜单、站点名称深色模式、账号弹层宽度及站点编辑密度；
  原生 SwiftUI 实现已满足对应行为，无需重复引入 Flutter 组件修复代码。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展的版本统一同步至
  `2026.0918.01 (294)`。

### 2026.0915.02 (292) - 2026-09-15

- 执行详情改为结构化摘要，分开展示站点统计、流量、失败原因和成功站点，
  并移除原始 JSON 记录。
- 消息详情过滤重复的简略成功记录，保留耗时、部分数据未更新和失败原因。
- 更新页面重新设计版本摘要、更新内容和安装包区域；更新日志按新增、修复、
  优化和调整分类，并过滤 Markdown 空标题与提交哈希。
- 站点刷新、签到、辅种及任务手动执行优先显示服务端实际返回信息，后端未
  返回消息时才使用本地兜底文案。
- 服务端返回信息支持完整多行显示，操作结果在原停留时长基础上延长 2 秒。
- README 改为随每次代码修改同步维护，持续记录每次实际变更内容。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展的版本统一同步至
  `2026.0915.02 (292)`。

### 2026.0915.01 (290) - 2026-09-15

- 对照 Flutter 版本完成增量审查；该批变更仅涉及 Flutter 组件兼容调整，
  原生端接口、数据模型和移动端工作流无需变更。
- App 与两个 Safari 扩展的版本统一同步至 `2026.0915.01 (290)`。

## Native stack

- SwiftUI navigation and forms
- Native iOS 26 Liquid Glass navigation with an ultra-thin-material fallback
- Swift Concurrency and URLSession networking
- TDLibKit/TDLib for local Telegram user authorization and Bot check-in commands
- Keychain token and credential storage
- Account-scoped persistent caches for dashboard, sites, media catalogs,
  downloads, scheduled tasks, and notices
- A separate memory/disk image cache for public artwork and site icons; signed
  image URLs remain memory-only
- Swift Charts dashboard visualizations
- WebKit site browsing with Cookie, host-aware LocalStorage/token injection,
  User-Agent switching, JavaScript dialogs, file inputs, recoverable loading
  errors, and persistent current-site cleanup
- SF Symbols plus a new, project-local AppIcon

## GitHub unsigned IPA

The `Build Unsigned IPA` workflow runs on `macos-26` and builds with code
signing disabled. Every push to `main` produces a 30-day Actions artifact named
`Harvest-unsigned-<run number>`. Tags matching `v*` also publish the IPA and its
SHA-256 checksum to a GitHub Release.

An unsigned IPA cannot be installed directly on a stock iPhone. Sign the
artifact with your own Apple ID, development certificate, enterprise
certificate, or a compatible sideloading service before installation.

## Migration status

The migration audit maps active Flutter workflows to native screens and service
calls, including first-run defaults, account-scoped cache restoration,
download-refresh, and site-history parity. It does not treat static source
coverage as proof of runtime 1:1 behavior. Runtime parity still requires an
Xcode build and an integration pass against a reachable Harvest server. See
[`MIGRATION_AUDIT.md`](MIGRATION_AUDIT.md) for the current evidence and limits.

## Implemented core workflows

- HTTP/HTTPS login, server-provided first-run database defaults, setup,
  Keychain credentials, token refresh, complete login-history restoration,
  direct account switching, logout, and complete local-data cleanup
- TMDB/Douban catalogs, details, search history, combined resource search over
  cancellable/deduplicated SSE, incremental results, advanced filtering,
  downloader push, and cached catalog restoration
- Site overview, ten editable feature flags, daily/monthly status history,
  separate mail/announcement state, complete filters and sorting, timeline,
  levels, imports, structured/raw TOML generation, bulk operations,
  cache-consistent mutations, authenticated browsing, credential sync,
  extraction, and pausable bonus tools
- Configurable dashboard modules, traffic/server charts, privacy mode, current
  page screenshot sharing, a dedicated dashboard long image, and cached
  dashboard/site data with visible timestamps and in-app refresh
- Downloader setup, persistent 1-60 second refresh settings, automatic-stop
  countdown, pause/resume, WebSocket recovery, cached startup snapshots,
  deduplicated live frames, precomputed torrent filtering, bulk and advanced
  controls, categories, tags, trackers, limits, and push workflows
- Scheduled-task lifecycle, Cron editing, migration-task assistance, Markdown
  execution results, termination, deletion, result-history management, and
  stale-while-revalidate list restoration
- Notice lifecycle, unread and app badges, local notifications, Markdown detail,
  cached list restoration, gap-free APP/server log pause/resume, updates, backup/import, users,
  paginated authorization management, and maintenance

Local notice polling and APP-package downloads currently run while the app is
active. The target does not declare remote-push or background-transfer
entitlements, so a terminated app cannot receive new notices or continue an IPA
download in the background.

## Performance and cache behavior

- Dashboard share images and log share text are generated only when the user
  requests them; automatic refresh no longer performs those expensive renders.
- Downloader and server countdowns update through localized `TimelineView`
  content instead of publishing an entire screen every second.
- Downloader snapshots are loaded concurrently, duplicate WebSocket frames are
  ignored, and site/torrent filters reuse precomputed indexes and sorted arrays.
- Persistent business caches are isolated by server and username, capped at 12
  MiB per entry and 48 MiB total, expire after 45 days, and are excluded from
  device backup. Legacy cache files are sanitized on first access.
- Passwords, Cookie/LocalStorage, authorization headers, API keys, tokens,
  passkeys, authkeys, RSS credentials, and signed image URLs are never written
  into the new persistent snapshots.
