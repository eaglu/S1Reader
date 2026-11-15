# S1 Reader

[![CI](https://github.com/eaglu/S1Reader/actions/workflows/ci.yml/badge.svg)](https://github.com/eaglu/S1Reader/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/eaglu/S1Reader)](https://github.com/eaglu/S1Reader/releases)

非官方的 Stage1st（S1）论坛 iOS 客户端，SwiftUI 编写，无第三方依赖。

## 功能

- 版块列表：按分类展示全部版块，含子版块、今日发帖数；可搜索版块
- 主题列表：分页加载、下拉刷新、本地搜索主题/作者、"只看今日新帖"、每行显示"上次浏览后新增回复数"（+N）
- 帖子阅读：
  - 记住每个主题的阅读位置，下次打开直接回到上次那一楼
  - 楼层头像（无头像或加载失败时回退为首字圆形）
  - Discuz HTML 转 AttributedString（粗体、斜体、颜色、链接）
  - 引用回复单独渲染为灰底卡片（左侧强调色竖条 + 小字号），与自己的回复正文一眼可分
  - 麻将脸内联显示：`face2017` 全套 241 张表情（001–279 里的现有编号）内置在 App 里，本地优先、离线可用；不在内置集合里的表情（旧表情组、版块自定义）仍走网络并按需下载
  - 图片按需加载（带 Referer，防盗链）、不做圆角裁剪、点击全屏查看（整图适配、双指缩放 / 以点击处为中心的双击放大、拖动平移、左右滑动切换本帖其它图片、未放大时下拉关闭、左边缘右滑关闭）
  - 分页加载、跳到指定页（可直接输入页码）、只看楼主
  - 正文跟随系统字号（动态字体），引用块在浅色/深色下都有足够对比度
  - 长按楼层可复制文字、复制楼层链接、分享；工具栏收藏按钮 + 「…」菜单（只看楼主 / 跳页 / 刷新 / 分享主题 / 清除本帖图片缓存）
  - 跳到某一页（如最后一页）后继续向上滚动，会依次补载上一页，并把先前位于顶部的那一楼留在原位；iOS 18 起顶部下拉即自动触发，页脚会显示已加载的页码区间（如「第 398–400 / 483 页」）
  - 图片懒加载：只有真正滚进可视区域的图片才开始下载，列表预建的、跳页途中的楼不会提前抓图（iOS 18 起用 `onScrollVisibilityChange` 判定，iOS 17 回退为「出现即加载」）
  - 上下两个方向都"一次一页"：同一段滚动里触发的重复请求会被忽略，必须等列表位置变化后再次触边才加载下一页
  - 只有帖子页隐藏标签栏（论坛的帖子列表仍保留），且是否隐藏由导航路径决定，返回时标签栏跟着转场一起回来，不会先空出一块，只保留右下角回复按钮；iOS 26 起该按钮是系统 Liquid Glass 按钮（`.buttonStyle(.glass)`），与导航栏、标签栏同一材质，旧系统回退为实心强调色圆形
- 账号：使用 S1 账号登录（支持安全提问），登录态通过 Cookie 保持
- 收藏主题 / 取消收藏（收藏夹支持左滑移除）
- 提醒与收藏夹列表（提醒数显示在"我的"标签角标）
- 回复主题（发送后自动跳到最新页并滚动到自己的楼层）
- 投票帖：首楼下方用原生组件显示选项、票数与比例条（跟随动态字体与深浅色）；没投过可选可提交，提交成功后原地更新票数而不刷新帖子；已投票只读显示结果并注明「你投给了」；投票结束显示结果并标注「投票已结束」；未登录能看结果，提交位置换成「去登录」
- 会话过期自动回到未登录态（服务端返回 `to_login` 时清空 Cookie）

## 运行

```bash
open S1Reader.xcodeproj
```

选择 `S1Reader` scheme 和任意 iPhone 模拟器（iOS 17+）运行即可，无需配置任何 API Key。

构建环境：Xcode 27 / iOS 27 SDK（CI 使用 GitHub Actions 的 `xcode-27` 镜像）。用 iOS 26+ SDK 编译时，在 iOS 26 及以上系统会呈现 Liquid Glass 外观；用 iOS 27 SDK 构建时该外观由系统强制启用，无法通过 `UIDesignRequiresCompatibility` 关闭，iOS 17/18 设备仍是经典外观。

命令行构建：

```bash
xcodebuild -project S1Reader.xcodeproj -scheme S1Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## 测试

单元测试在 `S1ReaderTests/`（Swift Testing 之前的 XCTest，随 `S1Reader` scheme 一起构建）：

```bash
./scripts/test.sh                                        # 自动挑一台 iPhone 模拟器
./scripts/test.sh -only-testing:S1ReaderTests/HTMLTextTests   # 只跑一个文件
./scripts/test.sh --ui                                   # 界面冒烟测试（需要联网）
TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17' ./scripts/test.sh
```

脚本优先用已经启动的模拟器，不会为了跑测试再开一台。

覆盖的是不依赖网络的那一层：`HTMLParser` 的富文本/引用/图片/笑脸解析、`Stage1stLink` 的站内链接识别、各个 Codable 模型对 Discuz「字符串还是数字」的兼容、UserDefaults 存储（阅读进度、新回复、图片比例、访客回退）、`PostBodyCache` 与 `PostNodeMirror` 的缓存命中与淘汰。所有用例都不发请求、不读写真实 App 容器（`TemporaryDefaults` 给每个用例一个独立 suite），因此可以离线跑、可以并行。

回归测试是照着真实 bug 写的：`<` 当纯文本、`<script>` 里带 `<` 吞掉后文、`</p><p>` 多出一个空行、引用块后的正文以空行开头、`evilstage1st.com` 被当成站内链接、数字型 `newprompt` 解不出红点、只有日期的 `2024-11-12` 解析失败、`imageURLs` 只读 `src` 导致附件图没预取（比例未定 → 行高二次变化）。CI 的 `Test (simulator)` job 跑同一份脚本。

### 界面冒烟测试

`S1ReaderUITests/` 走 `S1ReaderUI` scheme（不在默认 scheme 里，不会拖慢单元测试）：启动 App → 点开一个版块 → 点开一个主题，检查各层正文确实渲染成了文字（`postBody-<pid>`）而不是骨架条（`postPlaceholder-<pid>`），再上滑六屏确认滚动出来的行也不是骨架条。版块正文那条断言就是当初“只显示灰色条”那个回归的形状。没网时用例以 `XCTSkip` 跳过，不会把 CI 拖红；截图作为附件留在 xcresult 里。

`ImageBrowserDismissTests` 用同一条路子打开图片查看器，用真实手势验它关不关得掉：未放大时下拉关闭、轻拉弹回、左边缘右滑关闭、放大后下拉只平移不关闭、横向拖动仍然翻页。手势只能这样验——`simctl` 注入不了触摸，`simvyn input swipe` 在 iOS 上直接报 unsupported。这几条也要联网（图片走外链）。

## 项目结构

```
S1Reader/
├── App/                 入口与根导航（TabView + NavigationStack）
├── Core/
│   ├── Networking/      APIClient（Discuz 移动端 API）、解码辅助、图片加载
│   ├── Models/          Forum / Thread / Post / Account
│   ├── HTML/            HTMLParser：帖子 HTML → 带样式的 AttributedString
│   ├── Intents/          App Intents：版块/主题实体、三条 intent、深链、Spotlight 索引
│   └── Store/           AppModel：全局状态（版块、登录态）
└── Features/
    ├── Boards/          版块列表
    ├── Threads/         主题列表
    ├── Thread/          帖子详情、楼层渲染、回复、跳页
    └── Account/         登录、提醒、收藏夹
S1ReaderTests/           单元测试（解析 / 解码 / 存储 / 缓存）
```

## Siri AI（App Intents，Developer Preview）

苹果 2026-11-03 起在 iOS/iPadOS/macOS/visionOS 27.3 beta 上开放 Siri AI Developer Preview：任何 app 都能用 App Intents 把自己的动作和内容接进 Siri AI，复杂任务用 app skills 编排。下面是从官方文档读出来的约束、这次实现的范围，以及在真机上的验证步骤。

参考文档：

- 公告 <https://developer.apple.com/news/?id=gdk2umrf>
- <https://developer.apple.com/documentation/appintents/siri-ai-developer-preview>
- Bringing custom actions and content to Siri / Orchestrating complex actions with app skills / Making app entities available in Spotlight / Verifying your App Intents implementation

### 文档给出的约束

- **没有新增 entitlement，也没有新增 Info.plist 声明。** Preview 的门槛只有三条：Apple Intelligence 可用机型、系统语言在支持列表里（英语 / 法语 / 日语 / 韩语 / 葡萄牙语 / 西班牙语；繁体中文、简体中文都还**不在**列表）、以及用开发签名或内部 TestFlight 分发。App Store 版本和外测 TestFlight **拿不到** Siri AI 能力，正式提审要等到明年春天。
- **自定义动作要变成 Siri 的工具**：给 intent 加 `@AppIntent(.tool)`（新宏，等价于 `ToolIntent`）。已经采用 Siri 支持的内置 schema（消息、邮件这类主域）的 intent 不要再加，否则重复。
- **实体要能被找到**：`IndexedEntity` + 命名 `CSSearchableIndex.indexAppEntities(_:)` 写进 Spotlight 语义索引——Siri AI 能 surface 索引里的任意实体，不再要求实体套系统 schema；`IndexedEntityQuery` 负责被要求重建索引时回填。属性用 `@Property` / `@ComputedProperty` 带 title 与 description；敏感字段用 `IntentAuthenticationPolicy`，不该给系统的用 `visibility: .internal`。模型可直接生成的实体走 `@AppEntity(.generable)` + `GenerableEntity`。
- **复杂任务用 app skills**：`Skills.skillsbundle/Skills/<小写名字>/SKILL.md`，frontmatter 只有 `name` 与 `description`（Agent Skills 的子集），正文上限 10000 字；Xcode 在编译期校验并编译进 app，系统在支持 Preview 的设备上索引。skills 只能给建议，不能强制确定性行为。
- **验证路径**：AppIntentsTesting 集成测试 → Shortcuts app 里试动作 → Spotlight 里试实体 → Siri 端到端；另有 Xcode 的 Siri Integration Advisor 和 SiriEvaluations 框架（两者都要 27.3 工具链）。Spotlight 索引在模拟器上不可靠，实体可发现性必须真机验证。

### 本机工具链的缺口

本机是 **Xcode 27.2 / iOS 27.2 SDK**，AppIntents 模块里**没有**：`@AppIntent(.tool)`、`ToolIntent`、`AppIntentTraits`、`GenerableEntity`、`@AppEntity(.generable)`、`IntentVisibility`、`CardSnippet`、`SiriEvaluations`，也不认识 `Skills.skillsbundle`（会把里面的 `SKILL.md` 拍平拷到 app 根目录）。

已经有的：`IndexedEntity` / `indexAppEntities`（iOS 18）、`OpenIntent`（iOS 16）、`EntityStringQuery`、`EnumerableEntityQuery`、`AppShortcutsProvider`。所以这次按「标准 App Intents 部分做完整、Siri AI 专属部分用开关隔离」来做，Xcode 27.2 能正常编译、iOS 17 的老机型也还能装。

### 这次实现的内容

| Intent | 参数 | 做什么 | 深链 |
| --- | --- | --- | --- |
| `OpenForumIntent`（`OpenIntent`） | `ForumEntity` | 打开版块的主题列表 | `s1reader://forum?fid=6` |
| `OpenThreadIntent` | `ThreadEntity?` / `keyword: String?` | 打开指定主题；只给关键词时按标题匹配第一条；都不给时打开最近读过的主题 | `s1reader://thread?tid=…` |
| `CheckNoticesIntent` | `speakUnreadCount: Bool = true` | 打开「我的 → 提醒」，并用缓存的未读数回话 | `s1reader://notices` |

- **实体**：`ForumEntity` / `ThreadEntity`，各配一个 `EntityStringQuery`；数据来自本地拷贝，`perform()` 与参数解析都不走网络。`ForumEntity` 用 `ForumDirectory`（`s1.forumDirectory`，含子版块展平），`ThreadEntity` 用 `RecentThreadStore`（`s1.recentThreads`，最近 60 个读过的主题）。
- **Spotlight**：两者都有 `IndexedEntity` 一致性（`@available(iOS 18.0, *)`，不改 app 的 iOS 17 最低版本），`S1SpotlightIndex` 用命名索引 `S1ReaderEntities` 捐赠版块与主题。
- **AppShortcutsProvider**：`S1Shortcuts` 给三条 intent 配了英文短语（Siri AI 目前不支持中文），参数值可以是中文（版块名、主题标题）。
- **深链**：`AppDeepLink` 解析/生成 `s1reader://`，`Info.plist` 注册 scheme；intent 不在 `perform()` 里阻塞，而是把路由写进 `PendingDeepLink`（defaults + 通知）再由界面消费。`RootView` 三条路都收：`.onOpenURL`（外部打开）、通知（app 已在前台）、`scenePhase` 变 active（app 被 intent 唤醒）。
- **未登录降级**：深链指向「提醒」/「收藏夹」而当前没有会话时，切到「我的」并弹登录 sheet（`AppModel.pendingLoginPrompt` → `AccountView`），不会是空白页或崩溃。
- **缓存刷新**：`AppModel` 每次成功拉 `forumindex`/会话后写版块表、未读徽标、并重建 Spotlight 索引；`ThreadDetailViewModel` 在主题头部到达后记一次最近主题。
- **skill**：`Skills.skillsbundle/Skills/stage1st-reader/SKILL.md`，描述「打开版块 / 打开主题 / 看提醒」三条动作的用法与禁忌（英文，与短语语言一致）。

### 没做 / 受 Phase 限制的部分

- `@AppIntent(.tool)` 与技能包**没有在 27.2 上编译**：三个 `perform()` 前的宏放在 `#if SIRI_AI_PREVIEW` 里，默认关闭。升级 Xcode 后打开即可，代码路径不用重写。
- `Skills.skillsbundle` 故意放在仓库根、**不在** app target 里：27.2 不认识这个 bundle 类型，会把它拍平（`SKILL.md` 掉到 bundle 根目录）。
- `CardSnippet` 卡片、「模型直接生成实体」、`SiriEvaluations` 评估、Xcode 的 Siri Integration Advisor 都要 27.3 工具链，未做。
- 真机 Siri AI 无法在这台 Mac 上验证（Apple Intelligence 资格校验过不去，模拟器也没有 Siri AI），只能靠「Debug 包 + 真机」实测，步骤见下。
- 区域与年龄限制是系统定的：EU 的 iOS/iPadOS/watchOS 暂不可用，13 岁以下不可用；服务端模型类功能还有每日用量上限。

### 真机实测步骤（iPhone，iOS 27.3 beta）

1. **语言与 Apple Intelligence**：设置 → Apple Intelligence 与 Siri → 语言改成 English (US)（Siri AI 目前不支持中文）；同一页打开 Apple Intelligence，等模型下载完成。
2. **装 Debug 包**：Xcode 里选真机直接 Run，或 `xcodebuild -project S1Reader.xcodeproj -scheme S1Reader -configuration Debug -destination 'id=<真机 UDID>' install`。首次启动后**先在 app 里逛一圈**（进两三个版块、点开一个主题）——版块表、最近主题和 Spotlight 索引都是这时候写进去的。
3. **确认动作已注册**：打开 Shortcuts → 新建快捷指令 → 搜索栏旁边的 Apps → S1，应能看到 `Open Board` / `Open Thread` / `Check Notices` 三个动作；Spotlight 搜版块名应出现 S1 的结果，点进去落到对应版块。
4. **说这三句**（app 在前台、后台都可以；后台时需要提到 app 名，短语里已经带了）：
   - “Hey Siri, **open a board in S1**” → 追问时用中文说版块名（例如「游戏论坛」），应进入该版块主题列表。
   - “Hey Siri, **open my last thread in S1**” → 打开最近读过的主题。
   - “Hey Siri, **how many notices do I have in S1**” → 进「我的 → 提醒」，并念出未读数（登录过、且 app 同步过徽标才有数字）。
5. **未登录降级**：退出登录后说第三句，应弹登录 sheet，而不是空页。
6. **外部深链**：Safari 打开 `s1reader://forum?fid=6`，应落到该版块（模拟器上已验证）。

注意 Preview 阶段的表述可能变：Siri AI 允许「不点 app 名」，但同一个请求在不同措辞下可能走不同 intent；如果某句话没命中，先在 Shortcuts 里跑同一个动作，确认 intent 本身没问题，再改措辞。

### 升级到 Xcode 27.3 之后的待办

1. 确认 `xcodebuild -version` 是 27.3；把 `SIRI_AI_PREVIEW` 加进 target 的 `SWIFT_ACTIVE_COMPILATION_CONDITIONS`（Debug/Release 都要），或直接删掉三个 intent 上的 `#if`。
2. 把 `Skills.skillsbundle` 加进 S1Reader target 的 Copy Bundle Resources，确认包内结构是 `Skills/stage1st-reader/SKILL.md`；Xcode 会校验 frontmatter，名字与目录必须一致。
3. 给 `ForumEntity` / `ThreadEntity` 的字段补 `@Property(title:description:)` 的 description，敏感字段按需加 `authenticationPolicy`，内部字段用 `visibility: .internal`。
4. 用 SiriEvaluations 写端到端评估（打开版块、最近主题、未读提醒各一条），接进 CI。
5. 用 CardSnippet 给「打开主题」「提醒」做卡片，替掉系统默认展示。
6. 视需要给「按标题找主题」加 `GenerableEntity`，让模型直接生成实体、省掉一次查询。
7. 提审前记得：Developer Preview 的能力在 App Store 版本里**不生效**，不要把依赖 `@AppIntent(.tool)` 的体验当成已上线功能写进发布说明。

### 验证记录

- `scripts/test.sh`：247 tests, 0 failures（新增 `AppDeepLinkTests` 9 条、`SiriIntentTests` 17 条，覆盖深链解析/往返、实体按 id 与关键词解析、最近主题排序与上限、未读数回话的四种分支）。
- `xcodebuild ... build`：BUILD SUCCEEDED（Xcode 27.2 / iOS 27.2 SDK，deployment target 17.0）。`appintentsmetadataprocessor` 正常写出 `Metadata.appintents`，三个动作会出现在 Shortcuts 里。
- 模拟器（iPhone 17, iOS 27.2）：`s1reader://forum?fid=6` 落到版块主题列表；未登录时 `s1reader://notices` 弹登录 sheet。
- 真机 Siri AI：待按上面的步骤在 iPhone (iOS 27.3) 上实测。

## 数据来源

使用 Discuz! 移动端 API（匿名可读）：

```
https://stage1st.com/2b/api/mobile/index.php?version=4&module=<module>&mobile=2
```

用到的 module：`forumindex`、`forumdisplay`、`viewthread`、`login`、`sendreply`、`favthread`、`mynotelist`、`myfavthread`。

注意：

- 图片、头像都需要 `Referer: https://stage1st.com/2b/`，否则返回 403
- 帖子 HTML 中的实体可能被二次编码（`&amp;amp;`），解析时连续解码两次
- 部分 module（如 `mypost`、`search`）在服务端有 PHP 告警，返回非 JSON，客户端会显示错误而不是崩溃

## 已知限制 / TODO

- 发新主题尚未实现（`newthread` 需要处理分类信息 threadtypes）
- 登录成功路径尚未用真实账号验证；登录失败会提示"登录失败，请检查账号密码"
- 提醒列表依赖 `mynotelist`，该 module 在未登录时返回 503；若登录后仍返回 503，界面会显示"服务端暂时不可用"
- 头像地址由 uid 推导（uid 464256 → `https://avatar.stage1st.com/000/46/42/56_avatar_middle.jpg`）；用户未设置头像时回退为首字圆形
- 图片缓存：内存（NSCache，上限约 96MB 解码像素）+ 磁盘（URLCache，300MB，`Library/Caches/.../s1-images`）；图片在后台线程按最长边 1600px 降采样解码，避免长帖里的大图吃内存；「我的 → 存储」可查看占用、清除全部，或进「图片缓存管理」按主题逐个清除（主题菜单里也有「清除本帖图片缓存」）
- 帖子接口 5xx 时自动用游客身份重试一次（S1 对某些帖子只在带登录 cookie 时报 `System Error` 503），并把该帖记进「接口降级」列表：之后打开直接走游客请求，不再先失败一次，界面不做额外提示；游客请求若也失败会自动撤销记录，下次重新尝试登录态。记录可在「我的 → 存储 → 清除接口降级记录」重置；错误页有「复制诊断信息」按钮，可导出 status / cookie 状态 / 错误页正文
- 保存图片：帖子里的图片长按（或全屏查看时点左上角按钮）可保存到相册，存的是原图而不是 1600px 的缓存版本
- S1 的 503（Discuz 的 "System Error" 页面）既表示服务器繁忙，也表示当前会话无权阅读该帖；客户端对 502/503/504/429 与网络错误自动重试 2 次，仍失败时错误页提供「重试」「在浏览器中打开」「登录」
- 投票数据来自 `viewthread` 的 `special_poll`（`polloptions` 是以 "1".."n" 为键的字典，不是数组）；投票用移动端 `module=pollvote` 的 POST，参数 `tid`/`formhash`/`pollsubmit=yes`/重复的 `pollanswers[]=<polloptionid>`。接口不直接说「我投过没有」，靠三条线索合起来判断：`special_poll.allowvote`（服务端算好的「当前账号现在能不能投」）、帖子 `closed`、以及本机记下的投票（`s1.pollVotes`，按账号分开存）；页面是以游客身份取回的时候（接口降级）不据此推断已投票，只看本机记录。无截止时间的投票 Discuz 会把 `expirations` 填成「取回时刻 + 86400」并在每次请求里滚动，所以只有带 `remaintime` 的才是真截止时间，否则到点也不会误标「投票已结束」
- 上次浏览时的回复数按主题保存在 UserDefaults（`s1.threadVisitSeen`，最多 800 条），列表里的 +N 就是当前回复数减去它
- 阅读位置按主题保存在 UserDefaults（`s1.readingPositions`，最多 300 条），按楼层号换算页码，主题被删楼或页码变化时最多偏移一楼
- 未实现：短消息、用户资料页、站内搜索（客户端只做本地标题/作者过滤）、编辑/删除自己的帖子
- iPad：标签栏在 iPad 上自动变为侧边栏（iOS 18+），长文阅读区最宽 760pt 居中；主题列表在 iPad 上用分组样式
- 引用回复可点：跳到被引用的楼层并短暂高亮；跳转后右下角按钮换成「返回刚才的楼」（图标从 ↩ 变成 ⇤），再点精确回到点击引用的那一楼（跨页也行，服务端 `findpost` 会给出所在页码）
- 滑到最新一页的底部继续上滑：检查有没有新回复，直接接在列表末尾
- 帖子里的 S1 站内链接直接在 app 内打开：`thread-123-1-1.html` / `forum.php?mod=viewthread&tid=…` / `goto=findpost&pid=…`（指到某一楼时会跳过去并高亮）/ `forum-6-1.html`；站外链接仍交给系统浏览器（Discuz 会把参数二次编码成 `&amp;amp;`，解析时已兼容）
- 轻量反馈：收藏/取消收藏、清除图片缓存、跳楼失败等短提示用底部胶囊 toast（约 2.2s 自动消失，带图标与触觉），不再打断阅读弹 alert；列表里加载失败用内联提示条（可「重试」或关闭），只有需要读者做决定的情况才用 alert
- 提醒与收藏夹首次加载用骨架行，和其它列表一致
- 动效（遵循 HIG「motion」与「feedback」）：骨架屏用自绘占位条 + 条内高光缓扫（1.6s 一轮）；图片下载完成后 0.18s 淡入；收藏按钮用符号弹动（`symbolEffect(.bounce)`）；列表里的 +N 徽标用弹簧缩放出现；新到的楼层（继续加载、底部检查到新回复）用 0.2s 淡入 + 10pt 上浮出现，且只对当次新增的楼生效（往上补载的楼层落在屏幕外，不做这个动画）；跨页跳楼时列表整体做一次交叉淡入淡出（换的是另一页内容，不做滚动动画，避免「瞬移」感）；「加载更早的回复」那行的状态文字用淡入切换；点开帖子图片用 iOS 18+ 的 zoom 转场（`matchedTransitionSource` + `navigationTransition(.zoom)`）；开启「减弱动态效果」时上述动画全部退化为静态或纯透明度变化
- App 图标为脚本生成的占位图

## 性能

帖子的正文只在需要时解析一次，解析结果按「pid + 字号」缓存在 `PostBodyCache`（`S1Reader/Core/HTML/PostBodyCache.swift`，上限 400 帖）：滚动离开再回来不会重解析；每页到达后会预解析一遍，行滚入时直接出内容。

解析结果同时还存一份在主线程上的 `PostNodeMirror`。`LazyVStack` 会把滚出窗口的行整个丢掉，回滚时重建的行 `@State` 是空的，只能等 actor 返回——那一帧行只有一行骨架的高度，等真正内容到位再撑开，于是它下方所有楼层被顶下去，表现就是「上滑时当前内容突然往下跳」。有了镜像，重建的行在第一次布局就能拿到最终正文，不会再出现「先一条线、再变成一大块」（同一段上滑脚本对比：反方向位移 1257pt、26 次方向翻转 → 0–267pt、0–4 次；正常滚动方向的位移曲线完全单调）。`didParse` 用来区分「还没解析」和「解析完就是空的」；麻将脸的内置图片也在布局时同步解析，避免文字行数在事后变化。

提取帖子图片不再走完整解析：`HTMLParser.imageURLs(in:)` 只扫 `<img>` 标签（实测每页 0.4–0.5ms，完整解析同页 13.4–13.7ms），并且只扫新到的楼层——多页追加时的工作量从 O(n²) 变成 O(n)。

调试：`S1_PERF=1` 打印每轮翻页实际解析了多少帖子、总耗时与均值；`S1_PERF_BENCH=1` 额外对比「只扫标签」与「完整解析」的耗时。

### 图片

帖子里的图片仍然是滚到屏幕上才加载（`visibleInScroll` 判定，离屏的只留占位）。占位块按图片真实宽高比撑开，所以图片落地时行高不会变、下面的内容不会跳：

- 宽高比优先从 `ImageAspectStore`（UserDefaults 键 `s1.imageAspects`，上限 800 条）读，之前看过的图立刻就有正确尺寸；
- 每页到达后在后台为这页的图批量探测尺寸（最多 4 个并发，只取前 64KB），所以滚到它们之前占位块就已经是最终高度，向上滚动不会再被回流打断；
- 单张图在滚到时如果还不知道尺寸，仍会先发一个 `Range: bytes=0-65535` 的小请求，用 ImageIO 增量解码读出像素宽高（实测 206 / 64KB 就能拿到 1049×862），拿到后占位块按真实比例调整一次；
- 图片本体下载完成后，比例会再校验并写入缓存。

全屏查看器（`ImageBrowser`）的三种退出手势按方向分工，互不抢键：

- **下拉关闭**只在图片没放大时成立。手势挂在 `TabView` 外层（`simultaneousGesture`，坐标空间取 `.global`，否则查看器跟着手指下移会把位移量喂回自己），先判主轴——纵向位移超过横向 1.4 倍才算「往下拉」，横向的仍交给 `TabView` 翻页。拖动时整个查看器跟手下移、背景按比例淡出，松手后位移过 28%（或快速甩过 55%）就关，否则弹回原位。
- **缩放后同一条下拉是平移图片**，不是关闭：`ZoomableImage` 的拖动手势只在 `currentZoom > 1` 时注册（`gesture(_:including:)` 的 `GestureMask`），没放大时它根本不存在，所以两个手势不可能同时命中。
- **左边缘右滑**是盖在 `TabView` 上的一条 22pt 热区，同样只认主轴为横向的拖动；翻页只有在这一条热区里才会让位。
- 关闭时不把查看器位置归零，直接把 `dismiss()` 交给 `.zoomPresentation`，图片从当前（可能已经下拉的）位置缩回帖子里的原位置，不会先跳回屏幕中央。
- VoiceOver 通过容器的 `accessibilityAction(.escape)` 关闭。

## 开发小工具

Debug 构建支持环境变量直达页面，方便截图和调试（模拟器无法点击 UI 时尤其有用）：

```bash
SIMCTL_CHILD_S1_OPEN="forum:6" xcrun simctl launch booted com.faye.S1Reader
SIMCTL_CHILD_S1_OPEN="thread:2206666" ...
SIMCTL_CHILD_S1_TAB=account SIMCTL_CHILD_S1_OPEN=login ...
```

- `S1_TAB=account` 打开"我的"标签
- `S1_OPEN=forum:<fid>` / `thread:<tid>` / `login` / `notices` / `favorites`
- `S1_SCROLL=<pid>` 打开主题后跳到指定楼层，用来检查滚动与阅读位置保存
- `S1_FORCE_503=1`（=2 连游客重试也失败）强制 `viewthread` 返回 503，用来检查游客兜底与错误页的诊断按钮
- `S1_CLEAR_IMAGES=1` 打开主题后清掉本帖图片缓存，并打印磁盘缓存占用变化，用来检查按主题清理
- `S1_SAVE_IMAGE=<url>` 启动时保存一张图片到相册，用来检查相册写入（模拟器无法点击菜单）
- `S1_VIEW_IMAGE=<url>` 打开主题后直接弹出图片查看器，用来检查全屏显示与缩放
- `S1_ZOOM=<倍数>` 配合 `S1_VIEW_IMAGE` 让查看器直接以该倍数打开（居中），用来检查放大后的取景范围
- `S1_PULL=<点数>` 配合 `S1_VIEW_IMAGE` 让查看器以下拉状态打开（模拟器拖不动），用来检查跟手位移与背景淡出；再加 `S1_PULL_CLOSE=1` 会在 1.5s 后松手，用来看关闭动画接到 zoom 转场的那一刻
- `S1_JUMP_SHEET=1` 打开主题后自动弹出「跳页」面板，用来检查页码输入框
- `S1_SEEN=<tid>:<replies>[,<tid>:<replies>]` 假装这些主题在只有 N 条回复时读过，用来检查列表里的 +N 徽标
- `S1_SEARCH=<关键词>` 预填搜索框，用来检查版块/主题的本地过滤
- `S1_LOADMORE=<n>` 打开主题后连续追加 n 页，用来检查分页与页码显示
- `S1_JUMP_PAGE=<n>` 打开主题后直接跳到第 n 页（配合 `S1_LOAD_EARLIER` 检查向上加载）
- `S1_LOAD_EARLIER=<n>` 连续向上补 n 页，用来检查跳页后的「加载更早的回复」（跳过一次性门控）
- `S1_LOAD_EARLIER_GATED=<n>` 用滚动触发的那条路径连点 n 次，用来验证同一段滚动只会补一页
- `S1_TOP_ROW=1` 配合 `S1_JUMP_PAGE` 把列表停在第 2 楼，让第一楼上方的那一行露出来
- `S1_QUOTE_TAP=<pid>` 打开主题后点一次引用（按钮会切成「返回原处」），用来检查跨页跳楼；配合 `S1_QUOTE_BACK=1` 会再点一次返回，`S1_QUOTE_FROM=<pid>` 指定「从哪一楼点的」以便检查返回落点
- `S1_MOTION_SLOW=<倍数>` 把新楼层入场、跨页跳楼的交叉淡入按倍数拉长，方便连拍检查
- `S1_FRESH_SCROLL=1` 配合 `S1_LOADMORE` 在追加后滚到首批新楼层，用来拍入场动画
- `S1_TOAST=<文字>` 打开主题后弹一条 toast（配合 `S1_TOAST_HOLD=<毫秒>` 调节停留时长），用来检查提示样式
- `S1_INLINE_NOTICE=<文字>` 强制显示列表内的错误提示条，用来检查重试/关闭样式
- `S1_NO_RESTORE=1` 忽略阅读位置记忆，让截图从第 1 页开始
- `S1_SLOW=<毫秒>` 让每个 API 请求先等待该时长，用来把加载态拉长以便连拍检查骨架屏与过渡动画
- `S1_CHECK_NEW=1` 打开主题后直接检查最新回复，用来检查底部上滑刷新（模拟器做不出下拉手势）
- `S1_DEMO=1` 注入假账号（S1er / 管理员）、假提醒与假收藏，用于在没有真实账号时检查登录后的界面：

```bash
SIMCTL_CHILD_S1_DEMO=1 SIMCTL_CHILD_S1_TAB=account \
  SIMCTL_CHILD_S1_OPEN=notices xcrun simctl launch booted com.faye.S1Reader
```

## 免责声明

非官方客户端，与 Stage1st 官方无关。请遵守论坛规则，不要用于爬取或批量抓取内容。

### 滚动帧数据（Release）

`scripts/perf-scroll.sh` 用 Release 包在模拟器上跑一段固定脚本：以 700pt/s 滚动 2400pt 再滚回来，两趟；记录每帧间隔、hitch（>1.5 帧）、hitch 占比、丢帧数、每帧主线程构建耗时，以及这段时间里列表重建了多少次（行 body、正文块、头像、过滤器、缓存命中/解析）。默认连跑三次取中位数，先跑一次热身丢弃。

```
scripts/perf-scroll.sh                              # 帖子 2206666
S1_PERF_THREAD=2268175 S1_PERF_RUNS=3 ./scripts/perf-scroll.sh
S1_PERF_NO_SELECTION=1 ./scripts/perf-scroll.sh     # 关掉一项做 A/B
```

探针在 `S1Reader/Core/Debug/PerfProbe.swift`，不带 `S1_PERF_SCROLL` 时每个计数器都只是一次 `Bool` 判断，App 行为不变；`S1_PERF_NO_*` 同理，只在测量时有意义。

**改前（中位数 3 次，Release，iPhone 18 Pro 模拟器 60Hz）**

| 帖子 | 帧均值 | p99 | hitch（>1.5 帧） | hitch 占比 | 平滑帧 | 行 body | 过滤次数 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2268175（40 楼 / 23 张图） | 17.5ms | 38.2ms | 35 | 4.5% | 95.5% | 75 | 63（2440 次比较） |
| 2206666（39 楼 / 纯文字） | 17.2ms | 33.3ms | 22 | 3.0% | 97.2% | 71 | 71（2760 次比较） |

**改后**

| 帖子 | 帧均值 | p99 | hitch | hitch 占比 | 平滑帧 | 行 body | 过滤次数 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2268175 | 17.4ms | 38.2ms | 33 | 4.3% | 95.8% | 75 | 4（80 次比较） |
| 2206666 | 17.1ms | 33.3ms | 18 | 2.5% | 97.8% | 71 | 4（80 次比较） |

**同一脚本下的逐项 A/B（2268175，中位数 3 次）**，用来区分「哪一项真的贵」：

| 关掉的东西 | hitch | hitch 占比 | p99 |
| --- | --- | --- | --- |
| 无（基线） | 35 | 4.5% | 38.2ms |
| 每段文字独立 `.textSelection` | 30 | 3.6% | 33.5ms |
| 行的 `.contextMenu` | 31 | 4.2% | 37.6ms |
| 图片淡入动画 | 32 | 4.4% | 38.6ms |
| 每行 `Divider()` | 34 | 4.2% | 37.7ms |
| 图片本身（只留占位块） | 38 | 4.8% | 38.5ms |
| 占位块里的 `ProgressView` | 37 | 4.9% | 38.2ms |
| 行的入场动画与高亮动画 | 38 | 4.8% | 38.2ms |

结论：这类内容上，SwiftUI 的 body 构建不是瓶颈（行 body 合计 24–55ms／14s，每帧 0.1ms 量级），每帧真正的时间花在系统侧的文字排版与 CGRect 合成上——Time Profiler 里主线程的热点是 `objc_msgSend`、Swift 元数据/协议查表、malloc/free、`memmove` 和 CoreAnimation 的 layer commit，没有哪个 App 函数独占。因此能改的就是减少每行挂上去的交互层：`.textSelection` 从「每个文字段一层」变成「整楼一层」。图片解码本来就在后台线程做降采样，A/B 也证明它不是这段脚本的瓶颈。

另外两条被数据否掉了：写 `scrollOffset`（每帧一次，14s 内 820 次）并不会让列表 body 重算（`listBodies=4`），因为这个状态没有被 body 读取；滚动中也没有重复解析（`cacheParses=40` 全部来自每页到达后的预热，`mirrorHits` 命中正常）。
