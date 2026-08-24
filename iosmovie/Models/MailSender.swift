import Foundation
import Network

struct MailConfig {
    static let senderEmail = "724625725@qq.com"
    static let senderAuthCode = "mijxmtcdoqmlbfdc"
    static let smtpHost = "smtp.qq.com"
    static let smtpPort: UInt16 = 465
    static let recipientEmail = "myxnit@163.com"
}

final class MailSender: ObservableObject {
    @Published var isSending = false
    @Published var resultMessage: String?
    @Published var isSuccess = false

    func sendFeedback(type: String, content: String, contact: String, completion: @escaping (Bool, String) -> Void) {
        print("[MailSender] sendFeedback start, type=\(type)")
        isSending = true
        resultMessage = nil

        let dateString = Self.currentDateString()
        let contactText = contact.isEmpty ? "未填写" : contact
        let subject = "影视王反馈-\(type)"
        let body = """
        反馈类型：\(type)
        反馈时间：\(dateString)
        联系方式：\(contactText)

        反馈内容：
        \(content)
        """

        Self.sendMail(
            host: MailConfig.smtpHost,
            port: MailConfig.smtpPort,
            username: MailConfig.senderEmail,
            password: MailConfig.senderAuthCode,
            from: MailConfig.senderEmail,
            to: MailConfig.recipientEmail,
            subject: subject,
            body: body
        ) { [weak self] success, message in
            print("[MailSender] sendFeedback callback, success=\(success), message=\(message)")
            DispatchQueue.main.async {
                self?.isSending = false
                self?.isSuccess = success
                self?.resultMessage = message
                completion(success, message)
            }
        }
    }

    private static func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    static func sendMail(
        host: String,
        port: UInt16,
        username: String,
        password: String,
        from: String,
        to: String,
        subject: String,
        body: String,
        completion: @escaping (Bool, String) -> Void
    ) {
        print("[SMTP] connecting to \(host):\(port)")
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tls
        )

        var hasFinished = false
        let finishOnce: (Bool, String) -> Void = { success, message in
            guard !hasFinished else { return }
            hasFinished = true
            print("[SMTP] finishOnce, success=\(success), message=\(message)")
            connection.cancel()
            completion(success, message)
        }

        let connectTimeout = DispatchWorkItem {
            print("[SMTP] connect timeout fired")
            finishOnce(false, "连接服务器超时，请检查网络后重试")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: connectTimeout)

        connection.stateUpdateHandler = { state in
            switch state {
            case .setup:
                print("[SMTP] state: setup")
            case .waiting(let error):
                print("[SMTP] state: waiting, error=\(error.localizedDescription)")
            case .preparing:
                print("[SMTP] state: preparing")
            case .ready:
                print("[SMTP] state: ready")
                connectTimeout.cancel()
                let session = SMTPSession(connection: connection)
                session.start(
                    username: username,
                    password: password,
                    from: from,
                    to: to,
                    subject: subject,
                    body: body,
                    completion: finishOnce
                )
            case .failed(let error):
                print("[SMTP] state: failed, error=\(error.localizedDescription)")
                connectTimeout.cancel()
                finishOnce(false, "连接失败：\(error.localizedDescription)")
            case .cancelled:
                print("[SMTP] state: cancelled")
            @unknown default:
                print("[SMTP] state: unknown")
            }
        }
        connection.start(queue: .global(qos: .utility))
    }
}

private final class SMTPSession {
    private let connection: NWConnection
    private var buffer = Data()
    private var currentStage = 0
    private var username = ""
    private var password = ""
    private var from = ""
    private var to = ""
    private var subject = ""
    private var body = ""
    private var completion: ((Bool, String) -> Void)?

    private var timeoutWorkItem: DispatchWorkItem?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(
        username: String,
        password: String,
        from: String,
        to: String,
        subject: String,
        body: String,
        completion: @escaping (Bool, String) -> Void
    ) {
        self.username = username
        self.password = password
        self.from = from
        self.to = to
        self.subject = subject
        self.body = body
        self.completion = completion

        print("[SMTP] session start, stage=\(currentStage)")
        scheduleTimeout()
        receive()
    }

    private func scheduleTimeout() {
        timeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            print("[SMTP] session timeout fired, stage=\(self?.currentStage ?? -1)")
            self?.finish(false, "发送超时，请稍后重试")
        }
        timeoutWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: workItem)
    }

    private func receive() {
        print("[SMTP] receive called, stage=\(currentStage), buffer=\(buffer.count)")
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self else { return }

            if let error = error {
                print("[SMTP] receive error, stage=\(self.currentStage), error=\(error.localizedDescription)")
                self.finish(false, "接收失败：\(error.localizedDescription)")
                return
            }

            if let data = data, !data.isEmpty {
                print("[SMTP] receive data, stage=\(self.currentStage), bytes=\(data.count), text=\(String(data: data, encoding: .utf8) ?? "<binary>")")
                self.buffer.append(data)
                self.processResponse()
            } else {
                print("[SMTP] receive empty data, stage=\(self.currentStage), call receive again")
                self.receive()
            }
        }
    }

    private func processResponse() {
        print("[SMTP] processResponse, stage=\(currentStage), buffer=\(buffer.count)")
        while true {
            guard let lineRange = buffer.range(of: Data("\r\n".utf8)) else {
                print("[SMTP] processResponse: no full line, buffer=\(buffer.count)")
                if buffer.count > 65536 {
                    finish(false, "服务器响应异常")
                } else {
                    receive()
                }
                return
            }

            let lineData = buffer.subdata(in: buffer.startIndex..<lineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...lineRange.upperBound)

            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                continue
            }

            print("[SMTP] response line: \(line)")

            let codeString = String(line.prefix(3))
            let isLastLine = line.count < 4 || line[line.index(line.startIndex, offsetBy: 3)] != "-"

            guard let codeValue = Int(codeString) else {
                print("[SMTP] invalid response code: \(line)")
                finish(false, "服务器响应格式错误")
                return
            }

            if !isLastLine {
                continue
            }

            handleResponse(code: codeValue)
            return
        }
    }

    private func handleResponse(code: Int) {
        print("[SMTP] handleResponse, stage=\(currentStage), code=\(code)")
        switch currentStage {
        case 0:
            guard code == 220 else {
                finish(false, "SMTP 握手失败")
                return
            }
            sendCommand("EHLO mail\r\n")
        case 1:
            guard code == 250 else {
                finish(false, "EHLO 失败")
                return
            }
            sendCommand("AUTH LOGIN\r\n")
        case 2:
            guard code == 334 else {
                finish(false, "认证请求失败")
                return
            }
            sendCommand("\(Data(username.utf8).base64EncodedString())\r\n")
        case 3:
            guard code == 334 else {
                finish(false, "用户名认证失败")
                return
            }
            sendCommand("\(Data(password.utf8).base64EncodedString())\r\n")
        case 4:
            guard code == 235 else {
                finish(false, "授权码认证失败，请检查 SMTP 授权码")
                return
            }
            sendCommand("MAIL FROM:<\(from)>\r\n")
        case 5:
            guard code == 250 else {
                finish(false, "发件人设置失败")
                return
            }
            sendCommand("RCPT TO:<\(to)>\r\n")
        case 6:
            guard code == 250 || code == 251 else {
                finish(false, "收件人设置失败")
                return
            }
            sendCommand("DATA\r\n")
        case 7:
            guard code == 354 else {
                finish(false, "DATA 命令失败")
                return
            }
            let mailData = buildMailData()
            sendRawData(mailData)
        case 8:
            guard code == 250 else {
                finish(false, "邮件发送失败")
                return
            }
            sendCommand("QUIT\r\n")
        case 9:
            finish(true, "发送成功")
        default:
            finish(false, "未知状态")
        }
    }

    private func sendCommand(_ command: String) {
        print("[SMTP] sendCommand, stage=\(currentStage) -> \(currentStage + 1), command=\(command.trimmingCharacters(in: .whitespacesAndNewlines))")
        currentStage += 1
        scheduleTimeout()
        connection.send(content: Data(command.utf8), completion: .contentProcessed { _ in })
        receive()
    }

    private func sendRawData(_ data: Data) {
        print("[SMTP] sendRawData, stage=\(currentStage) -> \(currentStage + 1), bytes=\(data.count)")
        currentStage += 1
        scheduleTimeout()
        connection.send(content: data, completion: .contentProcessed { _ in })
        receive()
    }

    private func buildMailData() -> Data {
        var message = ""
        message += "From: \(from)\r\n"
        message += "To: \(to)\r\n"
        message += "Subject: \(subject)\r\n"
        message += "MIME-Version: 1.0\r\n"
        message += "Content-Type: text/plain; charset=utf-8\r\n"
        message += "Content-Transfer-Encoding: base64\r\n"
        message += "\r\n"
        message += Data(body.utf8).base64EncodedString()
        message += "\r\n.\r\n"
        return Data(message.utf8)
    }

    private func finish(_ success: Bool, _ message: String) {
        print("[SMTP] finish called, success=\(success), message=\(message), stage=\(currentStage)")
        timeoutWorkItem?.cancel()
        connection.cancel()
        completion?(success, message)
        completion = nil
    }
}