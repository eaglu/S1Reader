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
  - 图片按需加载（带 Referer，防盗链）、不做圆角裁剪、点击全屏查看（整图适配、双指缩放 / 以点击处为中心的双击放大、拖动平移、左右滑动切换本帖其它图片）
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

## 项目结构

```
S1Reader/
├── App/                 入口与根导航（TabView + NavigationStack）
├── Core/
│   ├── Networking/      APIClient（Discuz 移动端 API）、解码辅助、图片加载
│   ├── Models/          Forum / Thread / Post / Account
│   ├── HTML/            HTMLParser：帖子 HTML → 带样式的 AttributedString
│   └── Store/           AppModel：全局状态（版块、登录态）
└── Features/
    ├── Boards/          版块列表
    ├── Threads/         主题列表
    ├── Thread/          帖子详情、楼层渲染、回复、跳页
    └── Account/         登录、提醒、收藏夹
```

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
- 上次浏览时的回复数按主题保存在 UserDefaults（`s1.threadVisitSeen`，最多 800 条），列表里的 +N 就是当前回复数减去它
- 阅读位置按主题保存在 UserDefaults（`s1.readingPositions`，最多 300 条），按楼层号换算页码，主题被删楼或页码变化时最多偏移一楼
- 未实现：短消息、用户资料页、站内搜索（客户端只做本地标题/作者过滤）、编辑/删除自己的帖子
- iPad：标签栏在 iPad 上自动变为侧边栏（iOS 18+），长文阅读区最宽 760pt 居中；主题列表在 iPad 上用分组样式
- 引用回复可点：跳到被引用的楼层并短暂高亮；跳转后右下角按钮变成「返回刚才的楼」，再点回到原处（跨页也行，服务端 `findpost` 会给出所在页码）
- 滑到最新一页的底部继续上滑：检查有没有新回复，直接接在列表末尾
- App 图标为脚本生成的占位图

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
- `S1_JUMP_SHEET=1` 打开主题后自动弹出「跳页」面板，用来检查页码输入框
- `S1_SEEN=<tid>:<replies>[,<tid>:<replies>]` 假装这些主题在只有 N 条回复时读过，用来检查列表里的 +N 徽标
- `S1_SEARCH=<关键词>` 预填搜索框，用来检查版块/主题的本地过滤
- `S1_LOADMORE=<n>` 打开主题后连续追加 n 页，用来检查分页与页码显示
- `S1_JUMP_PAGE=<n>` 打开主题后直接跳到第 n 页（配合 `S1_LOAD_EARLIER` 检查向上加载）
- `S1_LOAD_EARLIER=<n>` 连续向上补 n 页，用来检查跳页后的「加载更早的回复」（跳过一次性门控）
- `S1_LOAD_EARLIER_GATED=<n>` 用滚动触发的那条路径连点 n 次，用来验证同一段滚动只会补一页
- `S1_TOP_ROW=1` 配合 `S1_JUMP_PAGE` 把列表停在第 2 楼，让第一楼上方的那一行露出来
- `S1_QUOTE_TAP=<pid>` 打开主题后点一次引用（按钮会切成「返回原处」），用来检查跨页跳楼；配合 `S1_QUOTE_BACK=1` 会再点一次返回
- `S1_CHECK_NEW=1` 打开主题后直接检查最新回复，用来检查底部上滑刷新（模拟器做不出下拉手势）
- `S1_DEMO=1` 注入假账号（S1er / 管理员）、假提醒与假收藏，用于在没有真实账号时检查登录后的界面：

```bash
SIMCTL_CHILD_S1_DEMO=1 SIMCTL_CHILD_S1_TAB=account \
  SIMCTL_CHILD_S1_OPEN=notices xcrun simctl launch booted com.faye.S1Reader
```

## 免责声明

非官方客户端，与 Stage1st 官方无关。请遵守论坛规则，不要用于爬取或批量抓取内容。
