import SwiftUI

/// Value-based routes for the 我的 tab so deep links can push them.
enum AccountRoute: Hashable {
    case notices
    case favorites
    case imageCache
}

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var showLogin = false
    @State private var cacheBytes = 0
    @State private var showLogoutConfirm = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    if model.isLoggedIn, let member = model.member {
                        AvatarView(uid: member.uid, name: member.username, size: 52)
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.isLoggedIn ? (model.member?.username ?? "") : "未登录")
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section("功能") {
                if model.isLoggedIn {
                    NavigationLink(value: AccountRoute.notices) {
                        HStack {
                            Label("提醒", systemImage: "bell")
                            Spacer()
                            let unread = model.member?.unreadNotices ?? 0
                            if unread > 0 {
                                Text("\(unread)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }
                    NavigationLink(value: AccountRoute.favorites) {
                        Label("收藏夹", systemImage: "bookmark")
                    }
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Label("登录", systemImage: "person.badge.key")
                    }
                    Button {
                        showLogin = true
                    } label: {
                        HStack {
                            Label("提醒", systemImage: "bell")
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("登录后可用")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button {
                        showLogin = true
                    } label: {
                        HStack {
                            Label("收藏夹", systemImage: "bookmark")
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("登录后可用")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if model.isLoggedIn {
                Section {
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirm = true
                    }
                }
            }

            Section {
                HStack {
                    Text("图片缓存")
                    Spacer()
                    Text(cacheDescription)
                        .foregroundStyle(.secondary)
                }
                NavigationLink(value: AccountRoute.imageCache) {
                    Label("图片缓存管理", systemImage: "photo.on.rectangle.angled")
                }
                Button("清除缓存", role: .destructive) {
                    Task {
                        await ImageLoader.shared.clearCaches()
                        await refreshCacheUsage()
                    }
                }
                .disabled(cacheBytes == 0)
            } header: {
                Text("存储")
            } footer: {
                Text("帖子里的图片会缓存在本地，重新打开主题时不再重新下载。")
            }

            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("数据来源")
                    Spacer()
                    Text("stage1st.com")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("非官方客户端，与 Stage1st 官方无关。")
            }
        }
        .navigationTitle("我的")
        .refreshable {
            await model.refreshMember()
            await refreshCacheUsage()
        }
        .task { await refreshCacheUsage() }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .confirmationDialog("确定退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await model.logout() }
            }
            Button("取消", role: .cancel) {}
        }
        .navigationDestination(for: ThreadSummary.self) { thread in
            ThreadDetailView(summary: thread)
        }
        .navigationDestination(for: AccountRoute.self) { route in
            switch route {
            case .notices: NoticesView()
            case .favorites: FavoritesView()
            case .imageCache: ImageCacheView()
            }
        }
        .task {
            await model.refreshMember()
            #if DEBUG
            if ProcessInfo.processInfo.environment["S1_OPEN"] == "login" {
                showLogin = true
            }
            #endif
        }
    }

    private var cacheDescription: String {
        guard cacheBytes > 0 else { return "无" }
        return ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)
    }

    private func refreshCacheUsage() async {
        cacheBytes = await ImageLoader.shared.diskUsage()
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var subtitle: String {
        guard model.isLoggedIn, let member = model.member else {
            return "以游客身份浏览"
        }
        return member.groupTitle.isEmpty ? "已登录" : member.groupTitle
    }
}
