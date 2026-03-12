# OpenClaw 本机聊天 HTTP 入口

这个入口只做一件事：

> 接收本机自然语言请求，复用 `scripts/openclaw-router.sh`，再把结果以 HTTP JSON 返回。

它不是新的业务层，也不替代 OpenClaw Gateway / ACP Bridge。

---

## 1. 当前用途

适用场景：

- 你在本机想直接发自然语言，不想每次手敲 `query|explain|modify`
- 后续飞书入口想先复用一个稳定的本地 HTTP 适配层

当前默认仍然复用现有真值链路：

- `query|explain` -> `scripts/openclaw-query-entry.sh`
- `trigger` -> `scripts/openclaw-unified-entry.sh`
- `modify|create` -> `scripts/openclaw-acp-bridge-submit.sh`

路由判断顺序：

1. 先用当前配置好的 LLM 做意图路由
2. 如果 LLM 路由失败，再回退到本地关键词规则

---

## 2. 启动

```bash
cd /Users/apple/xinxisouji/gupiao1
./scripts/start-openclaw-chat-api.sh
```

默认地址：

```text
http://127.0.0.1:18889
```

---

## 3. 配置

当前从 `config/dsa.env` 读取以下变量：

```bash
OPENCLAW_CHAT_API_HOST=127.0.0.1
OPENCLAW_CHAT_API_PORT=18889
OPENCLAW_CHAT_API_TOKEN=
OPENCLAW_CHAT_API_TIMEOUT_SECONDS=120
OPENCLAW_CHAT_API_MODIFY_TIMEOUT_SECONDS=600
```

说明：

- `OPENCLAW_CHAT_API_TOKEN` 为空时，默认不鉴权，只建议本机使用
- 如需给飞书入口或其他本地客户端复用，建议配置 bearer token
- `OPENCLAW_CHAT_API_TIMEOUT_SECONDS` 用于 `query|explain|trigger`
- `OPENCLAW_CHAT_API_MODIFY_TIMEOUT_SECONDS` 用于 `modify|create`

---

## 4. 健康检查

```bash
curl http://127.0.0.1:18889/health
```

若开启 token，`/health` 仍可直接访问；只有 `/v1/chat` 受 bearer token 保护。

---

## 5. 聊天接口

### 5.1 最简单调用

```bash
curl -X POST http://127.0.0.1:18889/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"看看最近的统一汇总"}'
```

### 5.2 显式指定动作

```bash
curl -X POST http://127.0.0.1:18889/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"action":"query","target":"health","value":"today"}'
```

### 5.3 修改请求

```bash
curl -X POST http://127.0.0.1:18889/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"修改 futures 输出模板，但不要改别的"}'
```

### 5.4 开启 token 后调用

```bash
curl -X POST http://127.0.0.1:18889/v1/chat \
  -H "Authorization: Bearer <OPENCLAW_CHAT_API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"message":"解释一下今天的统一汇总"}'
```

---

## 6. 当前自然语言路由方式

当前实现不是单纯关键词硬匹配，而是两层：

### 第一层：LLM 意图路由

优先让当前配置好的模型判断：

- `query`
- `explain`
- `trigger`
- `modify`
- `create`

并提取：

- `target`
- `value`
- `instruction`

执行层仍然不变：

- `query|explain|trigger` -> 项目 router
- `modify|create` -> Claude Code 写入链路

### 第二层：关键词回退

如果 LLM 路由失败，再回退到最小关键词规则：

- `修改 / 新增 / 创建` -> `modify|create`
- `解释 / 怎么看 / 解读` -> `explain`
- `触发 / 运行 / 重新生成 / 立即发送` -> `trigger`
- 其他默认按 `query`

目标优先级：

- `健康 / 状态` -> `health`
- `期货` 或期货符号 -> `futures`
- `新闻 / 新鲜事 / 热点 / 舆情` -> `news`
- `股票 / 个股` -> `stock`
- 其他默认 `unified`

因此更稳的做法是：

- 简单场景直接用自然语言
- 需要精确控制时，显式传 `action/target/value`
- 涉及代码修改时，直接自然语言描述修改目标即可，底层会优先走 Claude Code 链路

---

## 7. 当前边界

这个入口当前只是在本机把“聊天请求”变成对 router 的调用。

它不负责：

- 飞书事件订阅
- 飞书签名校验
- OpenClaw Gateway 内部插件开发
- 股票/期货/新闻核心逻辑实现

如果后续接飞书，建议关系保持为：

```text
飞书消息 -> 飞书入口适配层 -> 本机聊天 HTTP 入口 -> scripts/openclaw-router.sh
```
