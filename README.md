# S1 Reader

[![CI](https://github.com/eaglu/S1Reader/actions/workflows/ci.yml/badge.svg)](https://github.com/eaglu/S1Reader/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/eaglu/S1Reader)](https://github.com/eaglu/S1Reader/releases)

非官方的 Stage1st（S1）论坛 iOS 客户端，SwiftUI 编写，无第三方依赖。

## 功能

- 版块列表：按分类展示全部版块，含子版块、今日发帖数
- 主题列表：分页加载、下拉刷新、"只看今日新帖"
- 帖子阅读：
  - 记住每个主题的阅读位置，下次打开直接回到上次那一楼
  - 楼层头像（无头像或加载失败时回退为首字圆形）
  - Discuz HTML 转 AttributedString（粗体、斜体、颜色、链接、引用）
  - 麻将脸内联显示
  - 图片按需加载（带 Referer，防盗链）、点击全屏缩放
  - 分页加载、跳到指定页、只看楼主
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
- 帖子接口 5xx 时自动用游客身份重试一次（S1 对某些帖子只在带登录 cookie 时报 `System Error` 503），成功则在顶部显示橙色提示；错误页有「复制诊断信息」按钮，可导出 status / cookie 状态 / 错误页正文
- 保存图片：帖子里的图片长按（或全屏查看时点左上角按钮）可保存到相册，存的是原图而不是 1600px 的缓存版本
- S1 的 503（Discuz 的 "System Error" 页面）既表示服务器繁忙，也表示当前会话无权阅读该帖；客户端对 502/503/504/429 与网络错误自动重试 2 次，仍失败时错误页提供「重试」「在浏览器中打开」「登录」
- 阅读位置按主题保存在 UserDefaults（`s1.readingPositions`，最多 300 条），按楼层号换算页码，主题被删楼或页码变化时最多偏移一楼
- 未实现：短消息、用户资料页、搜索、编辑/删除自己的帖子、深色模式细节打磨
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
- `S1_LOADMORE=<n>` 打开主题后连续追加 n 页，用来检查分页与页码显示
- `S1_DEMO=1` 注入假账号（S1er / 管理员）、假提醒与假收藏，用于在没有真实账号时检查登录后的界面：

```bash
SIMCTL_CHILD_S1_DEMO=1 SIMCTL_CHILD_S1_TAB=account \
  SIMCTL_CHILD_S1_OPEN=notices xcrun simctl launch booted com.faye.S1Reader
```

## 免责声明

非官方客户端，与 Stage1st 官方无关。请遵守论坛规则，不要用于爬取或批量抓取内容。
