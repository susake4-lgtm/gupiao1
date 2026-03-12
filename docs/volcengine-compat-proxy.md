# Volcengine 兼容代理

用途：

> 给 OpenClaw 一个本地 OpenAI-compatible 转发层，删除火山不支持的字段（当前已确认 `prompt_cache_key`），再转发到官方 `api/v3`。

默认监听：

```text
http://127.0.0.1:19090
```

启动：

```bash
cd /Users/apple/xinxisouji/gupiao1
./scripts/start-volcengine-compat-proxy.sh
```

健康检查：

```bash
curl http://127.0.0.1:19090/health
```

当前会做的兼容清洗：

- 删除 JSON 里的 `prompt_cache_key`

推荐配合 OpenClaw 使用方式：

- 把 OpenClaw provider 的 `baseUrl` 改成 `http://127.0.0.1:19090`
- 仍然保持模型名为 `doubao-seed-2-0-pro-260215`

这样 OpenClaw 继续按原来的 `openai-responses` 方式发请求，但本地代理会先做字段兼容，再转发给：

```text
https://ark.cn-beijing.volces.com
```
