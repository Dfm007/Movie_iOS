<?php
declare(strict_types=1);

// 通用公告接口：按 app_id 返回对应 App 的公告。
// 与发信接口 feedback.php 共用同一份 feedback_config.php 和同一个 token。

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function respond(int $status, array $payload): void
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    respond(405, ['success' => false, 'message' => '仅支持 GET 请求']);
}

$configFile = __DIR__ . '/feedback_config.php';
if (!is_file($configFile)) {
    respond(500, ['success' => false, 'message' => '服务端未配置']);
}

$config = require $configFile;
if (!is_array($config)) {
    respond(500, ['success' => false, 'message' => '服务端配置无效']);
}

$appID = trim((string) ($_GET['app_id'] ?? ''));
if (preg_match('/^[A-Za-z0-9_-]{1,64}$/', $appID) !== 1) {
    respond(400, ['success' => false, 'message' => '应用标识无效']);
}

// 与发信接口共用 apps 配置；非多 App 配置时退回顶层单 App 配置
$isMultiApp = isset($config['apps']) && is_array($config['apps']);
if ($isMultiApp) {
    if (!isset($config['apps'][$appID]) || !is_array($config['apps'][$appID])) {
        respond(403, ['success' => false, 'message' => '应用未授权']);
    }

    $app = $config['apps'][$appID];
    $configuredToken = trim((string) ($app['token'] ?? ''));
} else {
    $app = $config;
    $configuredToken = trim((string) ($config['api_token'] ?? ''));
}

if ($configuredToken !== '') {
    $authorization = (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? '');
    $customToken = (string) ($_SERVER['HTTP_X_FEEDBACK_TOKEN'] ?? '');
    $bearerToken = strncmp($authorization, 'Bearer ', 7) === 0
        ? substr($authorization, 7)
        : '';

    if (!hash_equals($configuredToken, $customToken) && !hash_equals($configuredToken, $bearerToken)) {
        respond(401, ['success' => false, 'message' => '接口认证失败']);
    }
}

$notice = isset($app['notice']) && is_array($app['notice']) ? $app['notice'] : [];

respond(200, [
    'enabled' => (bool) ($notice['enabled'] ?? false),
    'title' => (string) ($notice['title'] ?? ''),
    'message' => (string) ($notice['message'] ?? ''),
]);
