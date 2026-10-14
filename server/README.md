# 通用邮件发送接口（宝塔部署）

## 方案

App 通过 HTTPS 调用 `feedback.php`，服务器通过 SMTP 发信。服务端只维护 SMTP 凭据和每个 App 的收件地址；发件人名称和邮件标题由 App 传入，因此多个 App 可以共用同一个接口。

服务端固定 `from_email` 和 `to_email`，不允许 App 任意指定，避免接口被当成开放发信机。

## 宝塔部署步骤

1. 在宝塔面板中新建一个站点，例如 `feedback.example.com`，根目录设为 `/www/wwwroot/feedback-api`。
2. 上传本目录的 `feedback.php` 和 `feedback_config.php` 到站点根目录。
3. 填写全局 SMTP 和各 App 配置。
4. 确认站点使用 PHP 7.4 或更高版本，并启用 `openssl`、`mbstring` 扩展。
5. 在宝塔的站点设置中申请并强制启用 HTTPS。
6. 确认服务器出站可访问 SMTP 端口：465（SSL）或 587（STARTTLS）。
7. 建议在宝塔站点的 Nginx 配置中加入以下规则，禁止直接访问配置文件：

```nginx
location ~* /feedback_config\.php$ {
    deny all;
}
```

8. 用 curl 测试：

```bash
curl -X POST 'https://feedback.example.com/feedback.php' \
  -H 'Content-Type: application/json' \
  -H 'X-Feedback-Token: replace-with-a-long-random-token' \
  -d '{"app_id":"movie_ios","from_name":"影视王反馈","subject":"影视王反馈 - 问题反馈","type":"问题反馈","content":"测试反馈内容","contact":"test@example.com"}'
```

成功时返回：

```json
{"success":true,"message":"邮件已发送"}
```

## App 配置

部署完成后，把 `iosmovie/Info.plist` 改成实际配置：

```xml
<key>FeedbackEndpoint</key>
<string>https://feedback.example.com/feedback.php</string>
<key>FeedbackAppID</key>
<string>movie_ios</string>
<key>FeedbackFromName</key>
<string>影视王反馈</string>
<key>FeedbackSubject</key>
<string>影视王反馈 - {type}</string>
<key>FeedbackToken</key>
<string>replace-with-a-long-random-token</string>
```

`FeedbackSubject` 中的 `{type}` 会在 App 内替换成当前反馈类型。`FeedbackToken` 与服务器 `apps.movie_ios.token` 保持一致。

## 公告文件（notice.json）

同目录的 `notice.json` 提供 App 启动公告，和发信接口共用同一个站点，上传到站点根目录即可：

```
/www/wwwroot/smtp/notice.json   →   http://<服务器>:8787/notice.json
```

字段说明：

| 字段 | 说明 |
|---|---|
| `enabled` | 总开关。`true` 时用户每次打开 App 都会弹公告；`false` 时一律不弹 |
| `title` | 公告标题 |
| `message` | 公告正文 |

`title` / `message` 支持简单的富文本标记：

- `[br]`：换行（也可以直接在 JSON 里用 `\n`）
- `[color=#FF3B30]文字[/color]`：给文字上色

App 侧地址默认取自 `iosmovie/Info.plist` 的 `NoticeEndpoint`，但会被「配置页」里解析到的地址覆盖（见下一节）。示例：

```json
{
  "enabled": true,
  "title": "维护公告",
  "message": "服务器将于今晚 23:00 维护。[br][color=#FF3B30]期间可能无法播放。[/color]"
}
```

## 配置页（换服务器不用重新构建 App）

App 启动时会请求 `Info.plist` 里 `RemoteConfigURL` 指向的配置页（例如蓝奏云分享页），从中解析出真实的发信接口和公告接口：

```
[feedback]http://120.26.245.163:8787/feedback.php[/feedback]
[notice]http://120.26.245.163:8787/notice.json[/notice]
```

规则：

- 换服务器时只要改配置页里的这两个地址，**不需要重新构建 / 重新安装 App**。
- 解析成功后地址会缓存到本机；配置页打不开时用上次成功的缓存，再不行才回退到 `Info.plist` 里的默认地址。
- 配置页里没写某个标签时，该项继续用缓存 / 默认值，不会互相覆盖。

## 常见问题

- 返回 `发送失败，请稍后重试` 时，先把 `feedback_config.php` 顶部的 `'debug' => true` 临时打开，再请求一次即可看到具体 SMTP 错误；确认后改回 `false`。

- `SMTP connect failed`：检查宝塔安全组、服务器防火墙是否允许出站 465/587。
- `SMTP unexpected response`：检查邮箱是否开启 SMTP 服务，以及是否使用授权码而不是登录密码。
- `接口认证失败`：检查 `X-Feedback-Token` 与对应 App 的 `token` 是否一致。
- `应用未授权`：检查请求中的 `app_id` 是否存在于 `feedback_config.php` 的 `apps` 中。
- 如果使用 587 端口，把 `smtp.secure` 改为 `tls`；465 端口使用 `ssl`。
- `feedback_config.php` 不要提交到 Git，仓库已通过 `.gitignore` 忽略该文件。
