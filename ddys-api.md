# ddys.io 接口文档

## 站点信息

- 主站：https://ddys.io
- 备用域名：ddys.rest、ddys.baby、ddys.monster
- 访问要求：部分网络环境需要代理
- 认证：无，不需要登录或签名

## 统一请求头建议

所有请求建议携带：

```
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36
Accept: application/json, text/plain, */*
```

## 接口列表

### 1. 首页热门影视

请求：

```
GET https://ddys.io/api/hot-movies
```

返回示例：

```json
{
  "success": true,
  "data": [
    {
      "id": 6201,
      "title": "没关系，是爱情啊",
      "slug": "its-okay-its-love",
      "type": "剧集",
      "type_code": "series",
      "year": 2014,
      "rating": "8.8",
      "sources": 7,
      "source_desc": "4个在线源 · 3个下载源",
      "url": "/movie/its-okay-its-love"
    }
  ]
}
```

字段说明：

- id：影视数字 ID
- title：标题
- slug：详情页标识
- type：类型中文名，如 剧集、电影、动漫
- type_code：类型代码，series、movie、anime
- year：年份
- rating：评分，可能为 0.0 表示暂无评分
- sources：源总数
- source_desc：源描述
- url：详情页相对路径

### 2. 搜索建议

请求：

```
GET https://ddys.io/api/search-suggest?q={关键词}
```

关键词需要 URL 编码。

返回示例：

```json
{
  "success": true,
  "data": [
    {
      "title": "潜伏6",
      "slug": "insidious-out-of-the-further",
      "year": 2026,
      "rating": "0.0",
      "type": "电影",
      "type_code": "movie",
      "url": "/movie/insidious-out-of-the-further"
    }
  ]
}
```

字段同热门接口，但部分字段如 id、sources 可能缺失。

### 3. 影视详情页

请求：

```
GET https://ddys.io/movie/{slug}
```

返回：服务端渲染的 HTML 页面，播放源数据内嵌在页面 JavaScript 中。

关键数据点：

- movieId：影视数字 ID
- firstSource：第一个播放源对象，包含 url 和 format
- switchSource(id, url, format)：多源切换函数，源 ID 与 URL 均写在 HTML 中

播放源示例：

```
firstSource.url = "https:\/\/fengbao12.com\/video\/qianfu6\/672b5bed14b1\/index.m3u8"
firstSource.format = "m3u8"
```

注意：HTML 中的 URL 使用反斜杠转义斜杠，即 \/ 形式，解析时需要还原为 /。

## 播放地址提取逻辑

1. 请求详情页 HTML。
2. 用正则提取 firstSource 的 url 和 format。
3. 用正则提取所有 switchSource 调用中的源 ID、url、format。
4. 将 url 中的 \/ 替换为 /。
5. 剧集类资源可能包含多集列表，格式为 parseEpisodes(url) 解析，多集 URL 可能包含特殊分隔格式，需后续抓取剧集详情页确认。

## 已验证播放源示例

《潜伏6》第一源：

```
https://fengbao12.com/video/qianfu6/672b5bed14b1/index.m3u8
```

格式：m3u8

## 播放器说明

- 网页端使用 DPlayer 播放器。
- m3u8 格式可直接交给 AVPlayer 播放。
- 部分源可能有防盗链或 Referer 校验，iOS 端播放时可能需要携带 Referer 或自定义 User-Agent。
- 详情页播放源可能来自第三方域名，如 fengbao12.com。
