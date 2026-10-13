<?php

// 复制本文件为 feedback_config.php 后填写真实信息。
// feedback_config.php 已被 .gitignore 忽略，不要把真实授权码提交到仓库。
return [
    // 临时排错用。开启后接口会返回具体 SMTP 错误，确认后请改回 false。
    'debug' => false,

    // 所有应用共用的 SMTP 服务器配置。
    // QQ 邮箱: smtp.qq.com / 465 / ssl
    // 163 邮箱: smtp.163.com / 465 / ssl
    // 587 端口通常使用 tls (STARTTLS)
    'smtp' => [
        'host' => 'smtp.qq.com',
        'port' => 465,
        'secure' => 'ssl',
        'username' => 'your-sender@qq.com',
        'password' => 'your-smtp-auth-code',
        'timeout' => 20,
    ],

    // 每个 App 一个配置块。App 通过 app_id 选择自己的配置。
    'apps' => [
        'movie_ios' => [
            // App 的 Info.plist 中 FeedbackToken 必须与这里一致。
            'token' => 'replace-with-a-long-random-token',

            // 发件地址由服务器固定，App 只能设置发件人名称。
            'from_email' => 'your-sender@qq.com',
            'from_name' => '影视王反馈',

            // 收件地址由服务器固定，避免接口被当成任意收件人的发信机。
            'to_email' => 'your-receiver@example.com',

            // App 没有传 subject 时使用。
            'default_subject' => '影视王反馈',

            // 同一 IP 10 分钟内最多提交次数，设为 0 可关闭。
            'rate_limit_per_10_minutes' => 5,

            // 可选：覆盖全局 SMTP 配置。例如该 App 使用另一个邮箱发信。
            // 'smtp' => [
            //     'host' => 'smtp.163.com',
            //     'port' => 465,
            //     'secure' => 'ssl',
            //     'username' => 'another@163.com',
            //     'password' => 'another-auth-code',
            // ],
        ],

        // 其他 App 示例。
        // 'another_app' => [
        //     'token' => 'another-long-random-token',
        //     'from_email' => 'your-sender@qq.com',
        //     'from_name' => '另一个App',
        //     'to_email' => 'another-receiver@example.com',
        //     'default_subject' => '另一个App反馈',
        //     'rate_limit_per_10_minutes' => 5,
        // ],
    ],
];
