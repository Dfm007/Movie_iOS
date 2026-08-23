import SwiftUI

struct FeedbackView: View {
    @StateObject private var mailSender = MailSender()

    @State private var selectedType = "问题反馈"
    @State private var content = ""
    @State private var contact = ""
    @State private var showResult = false

    private let feedbackTypes = ["问题反馈", "功能建议", "其他"]

    var body: some View {
        Form {
            Section("反馈类型") {
                Picker("反馈类型", selection: $selectedType) {
                    ForEach(feedbackTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("反馈内容") {
                TextEditor(text: $content)
                    .frame(minHeight: 150)
            }

            Section("联系方式（选填）") {
                TextField("邮箱或 QQ", text: $contact)
            }

            Section {
                Button {
                    submit()
                } label: {
                    if mailSender.isSending {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("提交反馈")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(mailSender.isSending || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("意见反馈")
        .alert("提示", isPresented: $showResult) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(mailSender.resultMessage ?? "")
        }
    }

    private func submit() {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        mailSender.sendFeedback(
            type: selectedType,
            content: trimmedContent,
            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { _, _ in
            showResult = true
        }
    }
}