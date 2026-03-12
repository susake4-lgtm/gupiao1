# 客户 Mac 运行说明

适用当前真实可用方案：

- OpenClaw 官方飞书插件
- 本地 Volcengine 兼容代理
- gupiao1 本地脚本与 API

## 1. 当前建议架构

```text
飞书群 @机器人
-> OpenClaw 官方飞书插件
-> OpenClaw 本地网关
-> 本地 Volcengine 兼容代理
-> 火山方舟 API

查询项目结果
-> scripts/openclaw-router.sh
-> query|explain

修改项目
-> scripts/openclaw-router.sh
-> modify|create
-> ACP Bridge
```

## 2. 客户机器需要长期运行的服务

默认至少运行：

1. Volcengine 兼容代理
2. OpenClaw gateway

按需运行：

3. ACP Bridge
4. DSA API

## 3. 一键启动

推荐：

```bash
cd /Users/apple/xinxisouji/gupiao1
bash scripts/start-client-stack.sh --with-bridge --with-dsa-api
```

如果只需要飞书聊天与项目查询：

```bash
cd /Users/apple/xinxisouji/gupiao1
bash scripts/start-client-stack.sh
```

日志目录：

```text
logs/client-stack/
```

PID 文件：

```text
logs/client-stack/pids/
```

## 4. 手工启动顺序

如果不使用一键脚本，顺序固定为：

```bash
cd /Users/apple/xinxisouji/gupiao1
bash scripts/start-volcengine-compat-proxy.sh
bash scripts/start-openclaw.sh
bash scripts/start-acp-bridge.sh
bash scripts/run-dsa-api.sh
```

说明：

- `start-volcengine-compat-proxy.sh` 必须在 OpenClaw 前面
- 否则 OpenClaw 会直接打到火山接口，继续触发兼容问题
- `start-acp-bridge.sh` 当前通过 `scripts/claude-print-wrapper.sh` 强制调用 `claude -p`
- 并显式使用 `--model sonnet`，避免 Claude CLI 落到本机不可用的默认模型

## 5. 客户侧日常使用

在飞书群里：

- 只有 `@机器人` 才回复
- 例如：

```text
@机器人 你好
@机器人 看看最近的统一汇总
@机器人 解释一下今天的统一汇总
```

## 6. 常见排查

### 6.1 飞书里没有回复

先看 OpenClaw 是否在运行：

```bash
tail -n 50 logs/client-stack/openclaw.log
```

### 6.2 飞书里报 404 或 400

先看兼容代理是否在运行：

```bash
curl http://127.0.0.1:19090/health
```

如果不通，先重启：

```bash
bash scripts/start-volcengine-compat-proxy.sh
```

### 6.3 修改项目不生效

检查 ACP Bridge：

```bash
curl -H "Authorization: Bearer local-openclaw-only-token" http://127.0.0.1:8001/health
```

## 7. 当前关键端口

- OpenClaw: `18789`
- ACP Bridge: `8001`
- DSA API: `8000`
- Futures API: `8010`
- TrendRadar: `3334`
- Volcengine 兼容代理: `19090`
