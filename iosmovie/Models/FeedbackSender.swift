import Combine
import Foundation

private enum FeedbackServiceConfig {
    // App 只提供 app_id 和 token；发件人名称与邮件标题由服务端控制，
    // 这样改标题 / 发件人不用重新构建 App。SMTP 凭据也只留在服务器。
    /// 接口地址：来自远程配置页
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

        // 不传 from_name / subject：由服务端 apps.<app_id> 的 from_name / default_subject 决定，
        // 这样改发件人名称和邮件标题不用重新构建 App。
        let payload: [String: String] = [
            "app_id": FeedbackServiceConfig.appID,
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
