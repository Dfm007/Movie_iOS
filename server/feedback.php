<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function respond(int $status, bool $success, string $message): void
{
    http_response_code($status);
    echo json_encode(
        ['success' => $success, 'message' => $message],
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    );
    exit;
}

function textLength(string $value): int
{
    return function_exists('mb_strlen') ? mb_strlen($value, 'UTF-8') : strlen($value);
}

function sanitizeHeader(string $value, int $maxLength): string
{
    $value = str_replace(["\r", "\n"], ' ', trim($value));

    if (textLength($value) > $maxLength) {
        $value = function_exists('mb_substr')
            ? mb_substr($value, 0, $maxLength, 'UTF-8')
            : substr($value, 0, $maxLength);
    }

    return $value;
}

function normalizeRecipients($value): array
{
    $recipients = is_array($value) ? $value : [$value];
    $recipients = array_map(
        static function ($email): string {
            return trim((string) $email);
        },
        $recipients
    );

    return array_values(array_filter(
        $recipients,
        static function (string $email): bool {
            return $email !== '';
        }
    ));
}

function smtpReadResponse($socket): string
{
    $response = '';

    while (($line = fgets($socket, 1024)) !== false) {
        $response .= $line;
        if (preg_match('/^\d{3} /', $line) === 1) {
            break;
        }
    }

    if ($response === '') {
        throw new RuntimeException('SMTP connection closed');
    }

    return $response;
}

function smtpExpect($socket, array $expectedCodes): string
{
    $response = smtpReadResponse($socket);
    $code = (int) substr(ltrim($response), 0, 3);

    if (!in_array($code, $expectedCodes, true)) {
        throw new RuntimeException('SMTP unexpected response: ' . trim($response));
    }

    return $response;
}

function smtpCommand($socket, string $command, array $expectedCodes): string
{
    if (fwrite($socket, $command . "\r\n") === false) {
        throw new RuntimeException('SMTP write failed');
    }

    fflush($socket);
    return smtpExpect($socket, $expectedCodes);
}

function encodeHeader(string $value): string
{
    if (function_exists('mb_encode_mimeheader')) {
        return mb_encode_mimeheader($value, 'UTF-8', 'B', "\r\n");
    }

    return '=?UTF-8?B?' . base64_encode($value) . '?=';
}

function formatAddress(string $email, string $name = ''): string
{
    return $name === '' ? $email : encodeHeader($name) . ' <' . $email . '>';
}

function buildMessage(
    string $fromEmail,
    string $fromName,
    array $recipients,
    string $subject,
    string $appID,
    string $type,
    string $content,
    string $contact,
    string $remoteAddress
): string {
    $contactText = $contact === '' ? '未填写' : $contact;
    $typeLine = $type === '' ? '' : "类型：{$type}\r\n";
    $body = "应用：{$appID}\r\n"
        . $typeLine
        . "提交时间：" . date('Y-m-d H:i:s') . "\r\n"
        . "联系方式：{$contactText}\r\n"
        . "来源 IP：{$remoteAddress}\r\n\r\n"
        . "内容：\r\n{$content}\r\n";

    $headers = [
        'From: ' . formatAddress($fromEmail, $fromName),
        'To: ' . implode(', ', $recipients),
        'Subject: ' . encodeHeader($subject),
        'Date: ' . date('r'),
        'Message-ID: <' . bin2hex(random_bytes(16)) . '@' . (parse_url($fromEmail, PHP_URL_HOST) ?: 'localhost') . '>',
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset=UTF-8',
        'Content-Transfer-Encoding: base64',
    ];

    return implode("\r\n", $headers)
        . "\r\n\r\n"
        . chunk_split(base64_encode($body), 76, "\r\n");
}

function smtpSend(array $config, string $type, string $content, string $contact, string $remoteAddress): void
{
    $host = (string) $config['smtp_host'];
    $port = (int) $config['smtp_port'];
    $secure = strtolower((string) ($config['smtp_secure'] ?? 'ssl'));
    $username = (string) $config['smtp_username'];
    $password = (string) $config['smtp_password'];
    $fromEmail = (string) $config['from_email'];
    $fromName = (string) ($config['from_name'] ?? '影视王反馈');
    $subjectPrefix = (string) ($config['subject_prefix'] ?? '影视王反馈');
    $appID = (string) ($config['app_id'] ?? 'unknown');
    $timeout = max(5, (int) ($config['smtp_timeout'] ?? 20));
    $recipients = is_array($config['to_email']) ? $config['to_email'] : [$config['to_email']];

    $recipients = array_values(array_filter(array_map(
        static fn($email): string => trim((string) $email),
        $recipients
    )));

    if ($recipients === []) {
        throw new RuntimeException('No recipient configured');
    }

    $transport = $secure === 'ssl' ? 'ssl' : 'tcp';
    $context = stream_context_create([
        'ssl' => [
            'verify_peer' => true,
            'verify_peer_name' => true,
            'allow_self_signed' => false,
            'SNI_enabled' => true,
            'peer_name' => $host,
        ],
    ]);

    $errno = 0;
    $errstr = '';
    $socket = @stream_socket_client(
        $transport . '://' . $host . ':' . $port,
        $errno,
        $errstr,
        $timeout,
        STREAM_CLIENT_CONNECT,
        $context
    );

    if ($socket === false) {
        throw new RuntimeException("SMTP connect failed: {$errstr} ({$errno})");
    }

    stream_set_timeout($socket, $timeout);

    try {
        smtpExpect($socket, [220]);
        smtpCommand($socket, 'EHLO movie-feedback.local', [250]);

        if ($secure === 'tls') {
            smtpCommand($socket, 'STARTTLS', [220]);
            if (!stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
                throw new RuntimeException('SMTP STARTTLS failed');
            }
            smtpCommand($socket, 'EHLO movie-feedback.local', [250]);
        }

        smtpCommand($socket, 'AUTH LOGIN', [334]);
        smtpCommand($socket, base64_encode($username), [334]);
        smtpCommand($socket, base64_encode($password), [235]);
        smtpCommand($socket, 'MAIL FROM:<' . $fromEmail . '>', [250]);

        foreach ($recipients as $recipient) {
            smtpCommand($socket, 'RCPT TO:<' . $recipient . '>', [250, 251]);
        }

        smtpCommand($socket, 'DATA', [354]);
        $message = buildMessage(
            $fromEmail,
            $fromName,
            $recipients,
            $subjectPrefix,
            $appID,
            $type,
            $content,
            $contact,
            $remoteAddress
        );

        if (fwrite($socket, $message . ".\r\n") === false) {
            throw new RuntimeException('SMTP message write failed');
        }

        fflush($socket);
        smtpExpect($socket, [250]);
        smtpCommand($socket, 'QUIT', [221]);
    } finally {
        fclose($socket);
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, false, '仅支持 POST 请求');
}

$configFile = __DIR__ . '/config.php';
if (!is_file($configFile)) {
    respond(500, false, '服务端未配置');
}

$config = require $configFile;
if (!is_array($config)) {
    respond(500, false, '服务端配置无效');
}

$rawBody = file_get_contents('php://input');
if ($rawBody === false || trim($rawBody) === '') {
    respond(400, false, '请求内容为空');
}

$payload = json_decode($rawBody, true);
if (!is_array($payload)) {
    respond(400, false, '请求格式错误');
}

$appID = trim((string) ($payload['app_id'] ?? 'movie_ios'));
if (preg_match('/^[A-Za-z0-9_-]{1,64}$/', $appID) !== 1) {
    respond(400, false, '应用标识无效');
}

$isMultiApp = isset($config['apps']) && is_array($config['apps']);
if ($isMultiApp) {
    if (!isset($config['apps'][$appID]) || !is_array($config['apps'][$appID])) {
        respond(403, false, '应用未授权');
    }

    $app = $config['apps'][$appID];
    $smtpConfig = isset($config['smtp']) && is_array($config['smtp']) ? $config['smtp'] : [];
    if (isset($app['smtp']) && is_array($app['smtp'])) {
        $smtpConfig = array_merge($smtpConfig, $app['smtp']);
    }

    $configuredToken = trim((string) ($app['token'] ?? ''));
    $fromEmail = trim((string) ($app['from_email'] ?? ''));
    $toEmail = $app['to_email'] ?? '';
    $defaultFromName = (string) ($app['from_name'] ?? 'App 反馈');
    $defaultSubject = (string) ($app['default_subject'] ?? 'App 反馈');
    $rateLimit = max(0, (int) ($app['rate_limit_per_10_minutes'] ?? $config['rate_limit_per_10_minutes'] ?? 5));
} else {
    $smtpConfig = [
        'host' => $config['smtp_host'] ?? '',
        'port' => $config['smtp_port'] ?? 0,
        'secure' => $config['smtp_secure'] ?? 'ssl',
        'username' => $config['smtp_username'] ?? '',
        'password' => $config['smtp_password'] ?? '',
        'timeout' => $config['smtp_timeout'] ?? 20,
    ];

    $configuredToken = trim((string) ($config['api_token'] ?? ''));
    $fromEmail = trim((string) ($config['from_email'] ?? ''));
    $toEmail = $config['to_email'] ?? '';
    $defaultFromName = (string) ($config['from_name'] ?? '影视王反馈');
    $defaultSubject = (string) ($config['subject_prefix'] ?? '影视王反馈');
    $rateLimit = max(0, (int) ($config['rate_limit_per_10_minutes'] ?? 5));
}

if ($configuredToken !== '') {
    $authorization = (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? '');
    $customToken = (string) ($_SERVER['HTTP_X_FEEDBACK_TOKEN'] ?? '');
    $bearerToken = strncmp($authorization, 'Bearer ', 7) === 0
        ? substr($authorization, 7)
        : '';

    if (!hash_equals($configuredToken, $customToken) && !hash_equals($configuredToken, $bearerToken)) {
        respond(401, false, '接口认证失败');
    }
}

if (!filter_var($fromEmail, FILTER_VALIDATE_EMAIL)) {
    respond(500, false, '发件邮箱配置无效');
}

$recipientList = normalizeRecipients($toEmail);
if ($recipientList === []) {
    respond(500, false, '收件邮箱配置缺失');
}

foreach ($recipientList as $recipient) {
    if (!filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
        respond(500, false, '收件邮箱配置无效');
    }
}

foreach (['host', 'port', 'username', 'password'] as $key) {
    if (!isset($smtpConfig[$key]) || $smtpConfig[$key] === '') {
        respond(500, false, 'SMTP 配置不完整');
    }
}

$type = trim((string) ($payload['type'] ?? ''));
if (textLength($type) > 50) {
    respond(400, false, '类型过长');
}
$type = sanitizeHeader($type, 50);

$content = trim((string) ($payload['content'] ?? ''));
if ($content === '' || textLength($content) > 5000) {
    respond(400, false, '内容不能为空且不能超过 5000 字');
}

$contact = trim((string) ($payload['contact'] ?? ''));
if (textLength($contact) > 200) {
    respond(400, false, '联系方式过长');
}
$contact = sanitizeHeader($contact, 200);

$subject = trim((string) ($payload['subject'] ?? $defaultSubject));
if ($subject === '') {
    $subject = $defaultSubject;
}
if (textLength($subject) > 150) {
    respond(400, false, '邮件标题过长');
}
$subject = sanitizeHeader($subject, 150);

$fromName = trim((string) ($payload['from_name'] ?? $defaultFromName));
if ($fromName === '') {
    $fromName = $defaultFromName;
}
if (textLength($fromName) > 80) {
    respond(400, false, '发件人名称过长');
}
$fromName = sanitizeHeader($fromName, 80);

$mailConfig = [
    'app_id' => $appID,
    'smtp_host' => (string) ($smtpConfig['host'] ?? ''),
    'smtp_port' => (int) ($smtpConfig['port'] ?? 0),
    'smtp_secure' => (string) ($smtpConfig['secure'] ?? 'ssl'),
    'smtp_username' => (string) ($smtpConfig['username'] ?? ''),
    'smtp_password' => (string) ($smtpConfig['password'] ?? ''),
    'smtp_timeout' => (int) ($smtpConfig['timeout'] ?? 20),
    'from_email' => $fromEmail,
    'from_name' => $fromName,
    'subject_prefix' => $subject,
    'to_email' => $recipientList,
];

$remoteAddress = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');

if ($rateLimit > 0) {
    $rateFile = sys_get_temp_dir() . '/movie_mail_' . hash('sha256', $appID . '|' . $remoteAddress) . '.json';
    $handle = @fopen($rateFile, 'c+');

    if ($handle !== false) {
        $limited = false;

        if (flock($handle, LOCK_EX)) {
            $rawHits = stream_get_contents($handle);
            $hits = json_decode($rawHits === false ? '[]' : $rawHits, true);
            $hits = is_array($hits) ? $hits : [];
            $now = time();

            $hits = array_values(array_filter(
                $hits,
                static fn($timestamp): bool => is_int($timestamp) && $timestamp > $now - 600
            ));

            if (count($hits) >= $rateLimit) {
                $limited = true;
            } else {
                $hits[] = $now;
                ftruncate($handle, 0);
                rewind($handle);
                fwrite($handle, json_encode($hits));
                fflush($handle);
            }

            flock($handle, LOCK_UN);
        }

        fclose($handle);

        if ($limited) {
            respond(429, false, '提交过于频繁，请稍后再试');
        }
    }
}

try {
    smtpSend($mailConfig, $type, $content, $contact, $remoteAddress);
    respond(200, true, '邮件已发送');
} catch (Throwable $error) {
    error_log('Movie mail SMTP error: ' . $error->getMessage());
    $debug = !empty($config['debug']);
    $message = $debug ? '发送失败：' . $error->getMessage() : '发送失败，请稍后重试';
    respond(500, false, $message);
}
