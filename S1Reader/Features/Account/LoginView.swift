import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var username = UserDefaults.standard.string(forKey: "s1.lastUsername") ?? ""
    @State private var password = ""
    @State private var questionID = 0
    @State private var answer = ""
    @FocusState private var focus: Field?

    private enum Field { case username, password, answer }

    private let questions: [(Int, String)] = [
        (0, "无安全提问"),
        (1, "母亲的名字"),
        (2, "爷爷的名字"),
        (3, "父亲出生的城市"),
        (4, "您其中一位老师的名字"),
        (5, "您个人计算机的型号"),
        (6, "您最喜欢的餐馆名称"),
        (7, "驾驶执照最后四位数字")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("用户名", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .username)
                        .onSubmit { advance(from: .username) }
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .submitLabel(questionID > 0 ? .next : .go)
                        .focused($focus, equals: .password)
                        .onSubmit { advance(from: .password) }
                } header: {
                    Text("S1 账号")
                }

                Section("安全提问（未设置可忽略）") {
                    Picker("问题", selection: $questionID) {
                        ForEach(questions, id: \.0) { item in
                            Text(item.1).tag(item.0)
                        }
                    }
                    if questionID > 0 {
                        TextField("答案", text: $answer)
                            .submitLabel(.go)
                            .focused($focus, equals: .answer)
                            .onSubmit { advance(from: .answer) }
                    }
                }

                if let error = model.loginError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isLoggingIn {
                                ProgressView()
                            } else {
                                Text("登录").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit || model.isLoggingIn)
                } footer: {
                    Text("登录信息直接发送给 stage1st.com，客户端不会保存密码。")
                }
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                // Only grab the keyboard when there is something to type.
                if username.isEmpty { focus = .username }
            }
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && (questionID == 0 || !answer.isEmpty)
    }

    /// Return moves down the form and finishes on the last field, so the
    /// keyboard never strands the reader on the login button.
    private func advance(from field: Field) {
        switch field {
        case .username:
            focus = .password
        case .password:
            if questionID > 0 {
                focus = .answer
            } else {
                submitIfPossible()
            }
        case .answer:
            submitIfPossible()
        }
    }

    private func submitIfPossible() {
        guard canSubmit, !model.isLoggingIn else { return }
        focus = nil
        Task { await submit() }
    }

    private func submit() async {
        let success = await model.login(
            username: username,
            password: password,
            questionID: questionID,
            answer: answer
        )
        if success { dismiss() }
    }
}
