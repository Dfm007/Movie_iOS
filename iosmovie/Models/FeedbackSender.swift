import Foundation

final class FeedbackSender: ObservableObject {
    @Published var isSending = false
    @Published var resultMessage: String?
    @Published var isSuccess = false

    private let workerURL = URL(string: "https://feedback-sender-afpparrxxe.cn-hangzhou.fcapp.run")!

    func sendFeedback(type: String, content: String, contact: String, completion: @escaping (Bool, String) -> Void) {
        isSending = true
        resultMessage = nil

        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let payload: [String: String] = [
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
                if let error = error {
                    self?.finish(false, "提交失败：\(error.localizedDescription)", completion: completion)
                    return
                }

                guard let data = data else {
                    self?.finish(false, "提交失败：服务器无响应", completion: completion)
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = json["success"] as? Bool,
                       let message = json["message"] as? String {
                        self?.finish(success, message, completion: completion)
                    } else {
                        self?.finish(false, "提交失败：响应格式错误", completion: completion)
                    }
                } catch {
                    self?.finish(false, "提交失败：响应解析失败", completion: completion)
                }
            }
        }.resume()
    }

    private func finish(_ success: Bool, _ message: String, completion: @escaping (Bool, String) -> Void) {
        isSending = false
        isSuccess = success
        resultMessage = message
        completion(success, message)
    }
}