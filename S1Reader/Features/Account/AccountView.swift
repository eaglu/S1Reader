import SwiftUI

/// Value-based routes for the 我的 tab so deep links can push them.
enum AccountRoute: Hashable {
    case notices
    case favorites
}

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var showLogin = false
    @State private var showLogoutConfirm = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    if model.isLoggedIn, let avatar = model.member?.avatarURL {
                        RemoteImage(url: avatar, contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
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
                    Text("版本")
                    Spacer()
                    Text("0.2.0")
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
        .refreshable { await model.refreshMember() }
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

    private var subtitle: String {
        guard model.isLoggedIn, let member = model.member else {
            return "以游客身份浏览"
        }
        return member.groupTitle.isEmpty ? "已登录" : member.groupTitle
    }
}
