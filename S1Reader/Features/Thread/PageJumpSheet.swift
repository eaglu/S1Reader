import SwiftUI

/// Jump-to-page sheet: typing a number is faster than stepping when a thread
/// has hundreds of pages.
struct PageJumpSheet: View {
    let current: Int
    let total: Int
    var onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isEditing: Bool
    /// Fixed heights clip the form once the reader turns type up.
    @ScaledMetric(relativeTo: .body) private var detentHeight: CGFloat = 300

    init(current: Int, total: Int, onJump: @escaping (Int) -> Void) {
        self.current = current
        self.total = total
        self.onJump = onJump
        _text = State(initialValue: String(current))
    }

    private var lastPage: Int { max(total, 1) }

    /// Page number typed by the reader, or nil when it is out of range.
    private var enteredPage: Int? {
        guard let value = Int(text), value >= 1, value <= lastPage else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("页码")
                        Spacer()
                        TextField("1–\(lastPage)", text: $text)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($isEditing)
                            .frame(maxWidth: 120)
                    }
                    HStack {
                        Text("共")
                        Spacer()
                        Text("\(total) 页")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("输入 1 到 \(lastPage) 之间的页码")
                }
                Section {
                    Button(enteredPage.map { "跳到第 \($0) 页" } ?? "跳转") {
                        guard let page = enteredPage else { return }
                        onJump(page)
                        dismiss()
                    }
                    .disabled(enteredPage == nil || enteredPage == current)
                }
            }
            .navigationTitle("跳页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { isEditing = false }
                }
            }
            .onChange(of: text) { _, value in
                let digits = value.filter(\.isNumber)
                let trimmed = String(digits.prefix(5))
                if trimmed != value { text = trimmed }
            }
        }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .task {
            // Give the sheet time to slide in before taking focus.
            try? await Task.sleep(for: .milliseconds(350))
            isEditing = true
        }
    }
}
