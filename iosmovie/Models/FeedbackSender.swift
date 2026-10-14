import Combine
import Foundation

private enum FeedbackServiceConfig {
    // 每个 App 只配置自己的 app_id、发件人名称、标题模板和 token，SMTP 凭据留在服务器。
    /// 接口地址：优先取远程配置（配置页），其次 Info.plist 默认值
    static var endpoint: URL? {
        AppConfig.shared.feedbackEndpoint
    }

    /// 接口 token：与公告接口共用（Info.plist 的 RemoteConfigToken）
    static var token: String? {
        AppConfig.shared.token
    }

    /// App 标识：与公告接口共用（Info.plist 的 RemoteConfigAppID）
    static var appID: String {
        AppConfig.shared.appID
    }

    static let fromName: String = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "RemoteConfigName") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "影视王反馈" : value
    }()

    static let subjectTemplate: String = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "RemoteConfigSubject") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "影视王反馈 - {type}" : value
    }()

    static func subject(for type: String) -> String {
        subjectTemplate.replacingOccurrences(of: "{type}", with: type)
    }
}

final class FeedbackSender: ObservableObject {
    @Published var isSending = false
    @Published var resultMessage: String?
    @Published var isSuccess = false

    func sendFeedback(type: String, content: String, contact: String, completion: @escaping (Bool, String) -> Void) {
        isSending = true
        resultMessage = nil

        guard let endpoint = FeedbackServiceConfig.endpoint else {
            finish(false, "反馈服务未配置", completion: completion)
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        if let token = FeedbackServiceConfig.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Feedback-Token")
        }

        let payload: [String: String] = [
            "app_id": FeedbackServiceConfig.appID,
            "from_name": FeedbackServiceConfig.fromName,
            "subject": FeedbackServiceConfig.subject(for: type),
            "type": type,
            "content": content,
            "contact": contact
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            finish(false, "请求生成失败", completion: completion)
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.finish(false, "提交失败：\(error.localizedDescription)", completion: completion)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.finish(false, "提交失败：服务器无响应", completion: completion)
                    return
                }

                let serverMessage = Self.decodeMessage(from: data)
                if (200..<300).contains(httpResponse.statusCode) {
                    if let json = Self.decodeJSON(from: data),
                       let success = json["success"] as? Bool,
                       let message = json["message"] as? String,
                       !message.isEmpty {
                        self.finish(success, message, completion: completion)
                    } else {
                        self.finish(true, serverMessage ?? "发送成功", completion: completion)
                    }
                } else {
                    let fallback = "提交失败：服务器返回 \(httpResponse.statusCode)"
                    self.finish(false, serverMessage ?? fallback, completion: completion)
                }
            }
        }.resume()
    }

    private static func decodeJSON(from data: Data?) -> [String: Any]? {
        guard let data = data, !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decodeMessage(from data: Data?) -> String? {
        if let json = decodeJSON(from: data) {
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
            if let error = json["error"] as? String, !error.isEmpty {
                return error
            }
        }

        guard let data = data,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        return text
    }

    private func finish(_ success: Bool, _ message: String, completion: @escaping (Bool, String) -> Void) {
        isSending = false
        isSuccess = success
        resultMessage = message
        completion(success, message)
    }
}
