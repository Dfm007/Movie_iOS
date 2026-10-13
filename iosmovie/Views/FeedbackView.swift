import SwiftUI

struct FeedbackView: View {
    @StateObject private var feedbackSender = FeedbackSender()

    @State private var selectedType = "问题反馈"
    @State private var content = ""
    @State private var contact = ""
    @State private var showResult = false

    private enum Field: Hashable {
        case content
        case contact
    }

    @FocusState private var focusedField: Field?

    private let feedbackTypes = ["问题反馈", "功能建议", "其他"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "告诉我们你的想法",
                    subtitle: "你的反馈会直接发送到开发者邮箱"
                )

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("反馈类型")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        Picker("反馈类型", selection: $selectedType) {
                            ForEach(feedbackTypes, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(AppTheme.accent)
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("反馈内容")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        TextEditor(text: $content)
                            .font(.body)
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(minHeight: 150)
                            .focused($focusedField, equals: .content)
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("联系方式（选填）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        TextField("邮箱或 QQ", text: $contact)
                            .font(.body)
                            .foregroundColor(AppTheme.textPrimary)
                            .textFieldStyle(PlainTextFieldStyle())
                            .focused($focusedField, equals: .contact)
                    }
                }

                Button {
                    submit()
                } label: {
                    if feedbackSender.isSending {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.black.opacity(0.82))
                            Spacer()
                        }
                    } else {
                        Text("提交反馈")
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(feedbackSender.isSending || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                }
            }
        }
        .navigationTitle("意见反馈")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: $showResult) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(feedbackSender.resultMessage ?? "")
        }
    }

    private func submit() {
        focusedField = nil

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        feedbackSender.sendFeedback(
            type: selectedType,
            content: trimmedContent,
            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { success, _ in
            showResult = true
            if success {
                content = ""
                contact = ""
            }
        }
    }
}
