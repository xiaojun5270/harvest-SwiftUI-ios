# Harvest Native for iOS

This directory contains the native SwiftUI edition of Harvest. It is independent
from Flutter and CocoaPods and targets iOS 17 or later.

Open `Harvest.xcodeproj` with Xcode 26 or later, choose a development team, and
run the `Harvest` scheme. The backend API is shared with the Flutter client.

The native target keeps the production bundle identifier `com.ptools.harvest`
and uses version `2026.1021.01` with build `301`, so it can be signed as the next
update of the existing iOS app. Do not install a Flutter and native archive with
the same bundle identifier side by side.

## 代码更新记录

后续每次代码修改完成后均同步更新此处，无论是否调整版本号。同一发布版本的
改动持续追加到对应版本下，并按时间倒序排列；内容说明本次具体新增、修改、
优化或修复了什么，不堆叠提交哈希和无意义的内部日志。

### 2026.1021.01 (301) - 2026-10-21

- 修复 qB/Transmission 下载器活跃数和总数映射不准：两种客户端统一按 Flutter 同步的
  `activeTorrentCount`、`pausedTorrentCount`、`torrentCount` 精确字段解析，移除可能把
  `active_count`、`active_torrents` 等其他字段误当计数的兼容别名。
- 修复任务中心重新打开时空白或长期停留骨架屏：新建的任务视图模型不再被已完成的 App
  会话加载门闩拦截，当前模型无任务和执行记录时会独立完成缓存与接口初始化；已有模型
  仍不会重复加载。
- 修复设置页“管理、维护”双列网格共用 `List` 导航行导致点击一个入口时多个入口同时触发：
  网格改为独立按钮驱动统一导航路径，每块只响应自身点击区域，并移除系统附加的第二个
  箭头；清缓存、测试通知和重启服务仍保持独立操作。
- 彻底移除站点搜索栏下方重复显示“全部、条件、类型、标签、用户名、邮箱”的筛选结果
  标签条及其占位；筛选状态继续由按钮角标提示，筛选弹窗中选择的标签在点击应用后直接
  生效，不再依赖页面顶部进行二次选择。
- 修复下载器活跃数与总数首次获取后不再变化：数值直接消费 qB/Transmission 经后端
  WebSocket 返回的 `activeTorrentCount` 与 `torrentCount`；实时帧缺字段时按 Flutter
  相同链路读取单下载器 `main` 响应中的 `status/server_state`，不再使用未返回最新计数的
  `downloaders?with_status=true`，也不遍历或统计 `torrents` 数组。手动刷新强制同步，
  兼容校准最多每 60 秒一次，页面离开即取消。
- 下载器卡片切换为紧凑实时状态面板：移除重复占位的地址与种子路径信息框，顶部整合
  客户端、版本、在线状态及启用/辅种/主下载器标签；中部突出实时上下行速度并附会话
  流量，底部集中展示活跃数、总数和剩余空间，限速状态改为无嵌套卡片的单行提示。
- 移除任务中心重复的“TG 签到”分页、Bot 列表和独立定时编辑弹窗；TG Bot 的启用定时、
  执行时间与星期选择完整合并到站点页的 TG 签到编辑中，继续复用原配置字段，已有定时
  数据无需迁移，任务中心仅保留后端计划任务与执行记录。
- 重新设计设置页紧凑布局：账号与品牌图标合并，图标选择和恢复改为右侧快捷按钮；
  显示模式、强调色、密度和字号使用两列菜单，TMDB/豆瓣开关并排，自动刷新合并为
  单行预设与加减控件，管理及维护入口改为两列工具网格，关于信息压缩为一行。
- 移除站点卡片标题区重复的单独“通知”铃铛；保留已包含邮件与通知数量的未读总数、
  邮件、邀请和等级标识，站点详情中的通知数据与筛选能力不受影响。
- 统一执行详情与消息详情的任务结果分组规则：不再把“（已重试 N 次）”误当成下一条
  站点记录的分隔符，同一站点的请求失败、接口路径、DNS/TLS 原因和重试次数保持在
  同一条结果中；普通消息内容也不再于重试次数后强制断行。
- 修复仪表盘顶部“未读”长期显示为 0：仪表盘接口加载期间并行读取站点缓存中的邮件与
  通知数量，首屏直接合并结果，再由后台站点列表请求校准最新值并持久化；校准失败不再
  阻塞仪表盘主体数据或弹出错误提示。
- 修复站点图标稳定缓存键改造后 `RemoteImageCandidate.id` 缺少显式返回值导致的 Swift
  编译失败，恢复 GitHub Actions 无证书 IPA 构建所需的有效 getter。
- 全局移除流光、呼吸灯和 shimmer 动效：图标、圆形边框、站点状态标识和进度条改为
  静态呈现，避免点击页面或切换 Dock 时重新创建动画层造成卡顿。
- 移除所有页面顶部的缓存提示条，缓存仍继续用于首屏恢复和离线展示，但不再占用
  页面顶部空间或显示缓存时间。
- 站点汇总栏的“可用、未签到、未读”快捷筛选不再在搜索栏下重复显示同一筛选标签；
  手动打开筛选面板并应用后恢复正常筛选标签展示。
- 修复站点自定义图标在滑动、列表重建和重新进入页面时偶发消失：站点图标使用不含
  Authorization 的稳定缓存 key，同步复用内存解码图，并从全部持久候选恢复离线图片；
  候选变化和网络重试期间保留上一张成功图，不再先回退默认图标。
- 增加 App 会话级首次加载门闩：仪表盘、站点、下载、任务、资讯和搜索站点配置在
  当前账号首次进入时加载一次，后续未退出 App 的页面切换直接复用内存和缓存数据；
  手动刷新、下拉刷新、账号切换仍会主动请求。
- 移除站点卡片刷新时覆盖整块内容的白色遮罩、卡片内转圈和进度提示，刷新反馈统一
  使用全局悬浮窗，刷新期间继续显示卡片原有数据和 Liquid Glass 外壳。
- 优化 Dock 切换性能：非当前 Tab 的流光、呼吸等 Core Animation 自动暂停，切换完成
  后延迟恢复当前页动效，避免多个页面在系统切换动画期间同时占用渲染资源。
- Dock 选择从全局 `AppState` 发布状态拆为主界面本地状态，普通 Tab 点击不再触发所有
  隐藏页面同时重算 `body`；登录、权限变化和外部搜索请求仍可正常切换目标页面。
- 站点小指标取消逐项流光，仅保留上传、下载主指标和站点 Logo 动效；仪表盘与站点
  每个页面实例只在首次进入时加载，后续 Dock 切换不再按 60 秒间隔触发刷新。
- 下载器实时连接和服务器监控延后至切换动画结束；下拉刷新、手动刷新和全局自动刷新
  保持原有行为，不受 Dock 切换策略影响。
- 仪表盘“近 7 天增量排行”关闭标题、上传下载图标流光及前三名进度条移动高光，
  保留静态颜色、排行和增量对比。
- TG 签到页顶部快捷入口改为带文字的统一工具组，明确显示“签到、账号、添加”；替换
  部分系统无法显示的账号符号，批量签到期间显示“执行中”进度状态。
- 搜索入口改用系统原生 `TabRole.search`；iOS 26 Liquid Glass Dock 自动将搜索按钮
  与主导航标签组分离，iOS 17 继续使用兼容的普通搜索 Tab。
- 下载器卡片改为单层 Liquid Glass 外壳：在线状态合并到标题区，启用/辅种保留紧凑
  标签，地址路径、上传下载及活跃/总数/剩余使用分隔线组织，移除多层圆角模块并压缩高度。
- 下载器实时帧未返回种子计数时，卡片显示读取状态并在首屏呈现后按顺序读取一次计数
  摘要；只解析活跃、暂停和总数，不构建完整种子模型，结果写入轻量缓存。
- 仪表盘“站点状态、站点上传分布、站点下载分布、做种分布”关闭图标边缘流光和
  前三名进度条移动高光，保留静态语义色、排行与容量进度。
- 站点卡片移除按可用状态染色的绿色或红色外圈；iOS 26 改用原生 Liquid Glass
  圆角表面，旧系统使用无色 `ultraThinMaterial` 回退，异常状态仍由警告条明确展示。
- 修复站点排序按钮的双层箭头重叠，改为单一升序或降序箭头直接表达当前方向。
- 降低站点卡片指标区的色彩疲劳：上传、下载保留实心语义色，其余小指标改用低饱和
  图标、浅色底和弱流光，长列表中不再由八个高饱和色块同时争夺视觉焦点。
- 站点指标色收敛为活动、传输、资产和辅助四组，分享率继续按风险动态着色；指标区
  与最近时间区改用中性背景，状态含义仍可区分并兼容深色模式。
- 站点 Tab 隐藏全局顶部品牌与截图、消息、设置导航栏，移除截图标记的大块顶部占位；
  其他页面继续保留原有全局工具栏和 Liquid Glass 导航效果。
- 站点搜索栏右侧的排序、筛选、添加入口合并为统一材质工具组，使用等宽图标、共享
  圆角背景、细描边和分隔线；筛选数量及排序方向改为按钮内部紧凑角标。
- 原导航栏中的刷新全部、全部签到迁移到站点操作菜单，与添加站点、上传配置、生成
  配置和站点时间轴统一管理，隐藏顶部导航后功能仍完整保留。
- 优化下载器主页首屏：只读取轻量下载器缓存和配置，不再回退解码包含全部种子的
  大型快照，也不再为活跃数、总数在首屏并发拉取每个下载器的完整种子列表。
- 下载器实时状态连接提前到配置请求之前建立并暂存首帧，配置返回后立即按 ID、名称
  和 qB/TR category 别名合并；关闭自动刷新时仍执行一次限时状态快照。
- 扩充活跃、暂停和种子总数的嵌套字段解析，保留实时帧未返回的缓存计数，修复下载器
  卡片活跃数、总数长期显示为 0 或无法更新的问题。
- 新增原生设计系统文件，统一颜色、间距、圆角、页面边距、卡片表面与动效时长；
  现有 `HarvestTheme` 保持兼容，公共卡片已切换到统一令牌，避免页面样式继续漂移。
- 首屏加载由单一转圈提示改为复用硬件加速 shimmer 的卡片骨架；手动刷新、签到和
  管理操作的成功、失败、取消结果增加原生触觉反馈，不引入额外动画依赖。
- 仪表盘核心卡片改为紧凑 Bento 信息区，集中展示今日上传/下载、站点数、下载中、
  未读和实时上下行速度；服务器采样可用时直接显示双线微型速率波形，流量趋势图
  支持拖动选择日期并查看对应上传、下载数据。
- 站点异常卡片增加凭证提醒条以及编辑凭证、重试连接快捷入口；站点标签和类型筛选
  改为两列选择芯片，保留原有筛选状态与接口逻辑。
- 下载任务按下载、做种、暂停和错误状态显示双色胶囊进度条；批量选择操作改为底部
  悬浮材质栏，保留全选、取消全选和完整批量管理能力。
- TG 签到执行记录新增可持久化步骤时间轴，记录 Bot 定位、命令发送、回复、面板操作、
  结果解析和企业微信转发；点击节点可查看对应原始返回，旧历史无需迁移即可兼容显示。
- 将设计系统和 TG 时间轴拆为独立 Swift 文件并纳入 Xcode 工程，开始降低超大功能文件
  的维护压力；继续使用 Swift Charts、原生 Sheet 和现有 Core Animation，不增加三方包。
- 对照 Flutter `a5801bcb...b2e4c7f2` 完成增量审查：Flutter sheet 路由层重写、
  站点筛选主题 token 接入和移动搜索工具条 SafeArea 修复均属于 Flutter 组件实现；
  原生 SwiftUI 已使用系统 sheet、主题和导航安全区，无对应接口或功能代码需要复制。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展的版本统一同步至
  `2026.1021.01 (301)`。

### 2026.1013.02 (300) - 2026-10-13

- 对照 Flutter `3559697e...a5801bcb` 完成增量审查：Android CI 的
  `flutter_inappwebview_android` ProGuard 补丁、Web SSE 条件导出类名修复和
  Flutter 依赖锁变化均不适用于原生 SwiftUI/URLSession 工程，无需复制代码。
- App、收割机助手 Safari 扩展和 CookieCloud Safari 扩展的版本统一同步至
  `2026.1013.02 (300)`。

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
