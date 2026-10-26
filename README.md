# Harvest iOS 原生版

Harvest iOS 原生版使用 SwiftUI 开发，与 Flutter 客户端共用后端接口。项目不依赖 Flutter、
CocoaPods 或第三方 UI 框架，最低支持 iOS 17，iOS 26 及以上使用系统 Liquid Glass 导航样式。

## 项目概览

- 工程：`Harvest.xcodeproj`
- 构建方案：`Harvest`
- Bundle ID：`com.ptools.harvest`
- 当前版本：`2026.1021.01 (301)`
- 主要入口：`Harvest/HarvestApp.swift`
- 公共接口、缓存和模型：`Harvest/Core.swift`
- 主页面：`Harvest/PrimaryFeatures.swift`、`Harvest/SecondaryFeatures.swift`
- 站点功能：`Harvest/SiteFeatures.swift`
- 下载器功能：`Harvest/DownloadFeatures.swift`
- Telegram 签到：`Harvest/TelegramCheckinFeatures.swift`

## 本地开发

开发环境需要 macOS、Xcode 26 或更高版本，以及 iOS 17 或更高版本的模拟器或设备。

1. 用 Xcode 打开 `Harvest.xcodeproj`。
2. 选择 `Harvest` 方案和目标设备。
3. 配置 Apple 开发团队后运行。
4. 登录后端服务，验证站点、仪表盘、下载器和搜索功能。

Windows 环境无法运行 Xcode，因此本地只能执行静态检查，不能替代 macOS 上的原生编译和真机验证。

## 无证书 IPA

仓库中的 `.github/workflows/build-unsigned-ipa.yml` 用于生成未签名 IPA：

- 推送到 `main` 会触发构建。
- 构建使用 `macos-26` 和 `Xcode_26.6`。
- 关闭代码签名，不需要开发证书。
- 构建产物名为 `Harvest-unsigned-<运行编号>`，保留 30 天。
- 推送 `v*` 标签时，同时发布 GitHub Release 和 SHA-256 校验文件。

示例构建命令：

```bash
xcodebuild \
  -project Harvest.xcodeproj \
  -scheme Harvest \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  clean build
```

未签名 IPA 不能直接安装到普通 iPhone，安装前需要使用 Apple ID、开发证书、企业证书或其他兼容的侧载方式签名。

## 技术组成

- SwiftUI、Swift Concurrency、URLSession
- Swift Charts 仪表盘图表
- WebKit 站点内置浏览器
- TDLibKit/TDLib Telegram 用户授权和 Bot 签到
- Keychain 保存令牌、密码和 Telegram 凭据
- 按服务器和账号隔离的磁盘缓存
- 公共图片和站点图标的内存/磁盘缓存
- `HarvestSafariExtension` 收割机助手 Safari 扩展
- `CookieCloudSafariExtension` CookieCloud Safari 扩展
- SF Symbols 和项目内置 App 图标

## 已实现功能

### 登录与账号

- 支持 HTTP/HTTPS 登录、令牌刷新和缺少令牌后的恢复流程。
- 支持首次配置、数据库类型读取、登录历史、账号切换和退出登录。
- 敏感凭据写入 Keychain，不写入普通业务缓存。
- 支持完整清理本机缓存、通知记录、搜索记录和会话数据。

### 站点

- 站点列表、缓存优先加载、后台刷新和下拉刷新。
- 站点图标持久化、离线显示、自定义图标和 GIF 图片。
- 站点搜索、条件筛选、标签筛选、类型筛选、账号筛选和多维排序。
- 站点详情、等级详情、签到、刷新、辅种、凭证编辑和外部浏览器跳转。
- 添加站点、上传配置、生成配置、站点时间轴和批量操作。
- 邮件、公告、未读数量、注册时间、最后活跃时间、保号和毕业状态展示。
- 站点页包含站点与 TG 签到入口；TG Bot 的定时配置位于 Bot 编辑页。

### 仪表盘

- 今日上传、今日下载、站点数、下载中、未读和实时上下行速度。
- 数据概览、站点状态、增量排行、月度数据、分布图和服务器资源图表。
- 仪表盘模块显示、隐藏、排序和高度设置。
- 本地缓存优先展示，后台更新，不因网络请求阻塞首屏。
- 支持仪表盘截图分享、长图分享和本机缓存清理。

### 下载器

- qBittorrent 和 Transmission 下载器管理。
- 下载器启用、停用、辅种、删除、编辑、连接检查和参数设置。
- 分类、标签、限速、Tracker、种子添加、批量操作和种子详情。
- 下载器卡片显示在线状态、版本、实时上下行速度、会话流量、活跃数、总数和剩余空间。
- 活跃数、暂停数和总数直接读取后端同步的 `activeTorrentCount`、`pausedTorrentCount`、
  `torrentCount`，不由 App 遍历种子列表计算。
- 实时状态使用 `/api/ws/downloader/speed` 和 `/api/ws/downloader`，卡片计数缺失时按 Flutter
  相同链路读取 `/api/option/downloaders/main/{id}` 的 `status/server_state`。

### 搜索与影视

- TMDB、豆瓣搜索、分类浏览、详情页、分页和封面缓存。
- TMDB 或豆瓣关闭时，资讯入口和导航栏按设置自动调整。
- 资源搜索支持可取消的 SSE、增量结果、去重、筛选和下载器选择。
- 种子封面优先使用种子详情中的豆瓣或 TMDB 链接。

### Telegram 签到

- Telegram 账号授权、API ID、API Hash、手机号、验证码和两步验证。
- Bot 添加、编辑、自动识别、多命令、结果关键词和面板按钮操作。
- Bot 独立统计、执行记录、步骤时间轴和企业微信转发。
- 定时签到配置位于 TG Bot 编辑页，包括启用状态、时间和星期。
- iOS 后台唤醒受系统策略限制，不能保证固定时间执行；未配置定时 Bot 时不提交后台任务。

### 任务、消息与维护

- 任务中心仅保留后端计划任务和执行记录，支持创建、编辑、启用、停用、执行、终止和删除。
- 消息列表、未读角标、全部已读、删除、消息详情和结构化执行结果。
- 备份与迁移、后端配置、通知机器人、用户中心、授权管理、日志中心和 Safari 扩展设置。

## 性能与缓存策略

- Dock 切换只改变当前 Tab，不再切换全局动效环境或延迟重算隐藏页面。
- 流光、呼吸灯、shimmer 和进度条高光均为静态呈现，避免无效的动画层和原生视图桥接。
- 页面使用 App 会话级首次加载门闩；页面切换优先复用内存和持久化缓存。
- 下载器速度帧去重，站点筛选和种子筛选使用预计算索引。
- 缓存按服务器和账号隔离，单条缓存最大 12 MiB，总缓存最大 48 MiB，超过 45 天自动过期。
- Cookie、LocalStorage、密码、令牌、Passkey、Authkey、RSS 凭据和签名图片地址不写入新的持久快照。

## 当前限制

- 未声明远程推送和后台传输权限，App 被系统终止后不能接收新的站内消息，也不能继续后台下载 IPA。
- Telegram 定时签到在后台是否唤醒由 iOS 决定，不能承诺固定时间执行。
- 真实的 1:1 功能一致性仍需要 macOS Xcode 构建、可访问的 Harvest 服务和真机联调确认。

## 更新记录

后续代码修改完成后继续追加到当前版本，按时间倒序记录实际新增、修复和调整内容。提交哈希、内部调试日志和与原生项目无关的 Flutter 构建细节不写入本节。

### 2026.1021.01 (301) · 2026-10-25

- 修复 qB 下载器实时状态匹配失败导致活跃数、总数长期停留在首次值：支持下载器 ID、
  `name-id-category` 和 `wsKey`，实时帧先解包 `data/info/status/server_state`。
- 修复速度 WebSocket 持续返回旧计数时，客户端因“字段存在”而跳过校准的问题；活跃数和总数
  按实时刷新设置从 `main.status` 重新同步，手动刷新和重新进入下载页立即强制同步。
- 修复实时状态合并回归：上传/下载速度、会话流量和连接状态持续使用 WebSocket 更新，部分帧不会
  清空其他下载器的实时状态。
- 优化站点首次进入：站点和站点配置响应的解析、索引及持久化整理移到后台任务，首帧优先显示缓存或
  已收到的站点数据，避免大对象处理阻塞页面滚动。
- qB 和 Transmission 统一只读取后端计数字段 `activeTorrentCount`、`pausedTorrentCount`、
  `torrentCount`（兼容后端下划线写法 `torrent_count`），移除容易串值的 `active_count`、
  `active_torrents` 等别名。
- 修复任务中心重新打开时空白或长期停留骨架屏，新建任务模型会独立完成缓存和接口初始化。
- 修复设置页管理、维护网格点击串联和重复箭头，每个入口使用独立按钮和统一导航路径。
- 移除站点搜索栏下方重复的筛选结果标签，筛选弹窗应用后直接控制列表，角标继续显示生效数量。
- 下载器卡片移除地址/路径重复信息框，改为实时状态面板，保留全部管理入口。
- 移除 Dock 切换时的动效环境切换、180ms 延迟任务和隐藏页面全树重算。
- 站点提醒图标、加载骨架和仪表盘进度条改为纯 SwiftUI 静态绘制，减少 `UIViewRepresentable` 和动画层开销。

### 2026.1021.01 (301) · 2026-10-22

- 移除任务中心 TG 分页，TG 定时配置移动到 TG Bot 编辑页。
- 统一消息详情与执行详情的站点错误分组，重试原因不再被拆成独立记录。
- 修复仪表盘未读数量读取和持久化，缓存优先展示，后台校准。
- 重新设计设置页的账号、外观、资讯开关、管理和维护布局。
- 移除站点卡片重复的通知铃铛。
- 修复无证书 IPA 构建中的 Swift 显式返回值错误。

### 2026.1013.02 (300)

- 完成 Flutter 增量审查，确认 Android 专用构建修复和 Web 专用实现不适用于原生 SwiftUI。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展版本统一。

### 2026.1009.01 (297)

- 增加豆瓣正在热映数据、TG 多命令、面板按钮、成功转发、Bot 自动识别和定时签到能力。
- 完成消息、下载器、站点编辑和搜索页面的原生交互补齐。

### 2026.0930.01 (296)

- 修复下载器实时字段解析、站点镜像选择、键盘收起、下载器管理入口和移动端表单布局。

### 2026.0928.01 (295)

- 完善资源搜索标题选择、站点筛选、下载器管理页和移动端大尺寸弹窗。

### 2026.0918.01 (294)

- 重做消息列表与详情、通知角标、站点长按、深色模式和主导航图标。

### 2026.0915.02 (292)

- 重做执行详情和更新页面，补充服务端返回信息展示、日志维护和 README 更新规则。

## 迁移审计

完整迁移证据和未覆盖的运行时验证项见 [`MIGRATION_AUDIT.md`](MIGRATION_AUDIT.md)。该文件是源代码层面的迁移清单，不代表已经完成真机运行认证。

维护 README 时请优先说明当前实际行为；历史版本只记录当时的变更摘要，若后续行为发生变化，以前面的“项目概览”和“功能范围”为准。
