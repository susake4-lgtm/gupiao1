# 飞书入口接到本机 OpenClaw 聊天 API

这层只做薄入口：

```text
飞书消息
-> 飞书事件订阅 HTTP 入口
-> http://127.0.0.1:18889/v1/chat
-> scripts/openclaw-router.sh
-> query|explain|trigger|modify|create
```

它和现有 `FEISHU_WEBHOOK_URL` 不是一回事。

- `FEISHU_WEBHOOK_URL`：模块把结果发到飞书
- 本文这个入口：飞书把消息发进项目

---

## 1. 当前实现

新增入口：

- [scripts/start-feishu-openclaw-adapter.sh](/Users/apple/xinxisouji/gupiao1/scripts/start-feishu-openclaw-adapter.sh)
- [feishu_openclaw_adapter/app.py](/Users/apple/xinxisouji/gupiao1/feishu_openclaw_adapter/app.py)

默认监听：

```text
http://127.0.0.1:18989
```

可用路径：

- `GET /health`
- `POST /feishu/events`
- `POST /webhook/feishu`

---

## 2. 配置项

当前从 `config/dsa.env` 读取：

```bash
FEISHU_OPENCLAW_HOST=127.0.0.1
FEISHU_OPENCLAW_PORT=18989
FEISHU_BASE_URL=https://open.feishu.cn
FEISHU_APP_ID=
FEISHU_APP_SECRET=
FEISHU_OPENCLAW_TIMEOUT_SECONDS=120
OPENCLAW_CHAT_API_URL=http://127.0.0.1:18889
OPENCLAW_CHAT_API_TOKEN=
FEISHU_GROUP_REQUIRE_MENTION=true
```

说明：

- `FEISHU_APP_ID / FEISHU_APP_SECRET` 用于获取 tenant access token
- `OPENCLAW_CHAT_API_URL` 指向刚补好的本机聊天入口
- 如果聊天入口开启 bearer token，这里同步配置 `OPENCLAW_CHAT_API_TOKEN`
- 当前默认只处理群聊消息，且必须 `@机器人`

---

## 3. 飞书侧要求

这里需要的是飞书应用的“事件订阅”入口，不是群机器人 webhook。

也就是说：

- 如果只是群机器人 webhook，它只能收系统往飞书发的消息
- 如果要让用户在飞书里发消息给 OpenClaw，必须有飞书应用消息入口

最小接法：

1. 创建飞书应用
2. 开启机器人能力
3. 开启消息事件订阅
4. 把订阅地址指到：

```text
http://<你的机器IP>:18989/feishu/events
```

5. 让飞书应用具备发消息权限

群里处理规则：

- 只处理 `chat_type=group`
- 默认要求消息里明确 `@机器人`
- 没有 `@机器人` 的群消息直接忽略

---

## 4. 启动顺序

建议按这个顺序：

1. 启动 OpenClaw
2. 启动 ACP Bridge
3. 启动本机聊天入口
4. 启动飞书入口适配层

命令：

```bash
cd /Users/apple/xinxisouji/gupiao1
./scripts/start-openclaw.sh
./scripts/start-acp-bridge.sh
./scripts/start-openclaw-chat-api.sh
./scripts/start-feishu-openclaw-adapter.sh
```

---

## 5. 本机验证

健康检查：

```bash
curl http://127.0.0.1:18989/health
```

飞书 challenge 模拟：

```bash
curl -X POST http://127.0.0.1:18989/feishu/events \
  -H "Content-Type: application/json" \
  -d '{"challenge":"test-challenge"}'
```

消息事件模拟：

```bash
curl -X POST http://127.0.0.1:18989/feishu/events \
  -H "Content-Type: application/json" \
  -d '{
    "schema":"2.0",
    "header":{"event_type":"im.message.receive_v1"},
    "event":{
      "message":{
        "message_id":"om_test",
        "chat_id":"oc_test",
        "chat_type":"p2p",
        "message_type":"text",
        "content":"{\"text\":\"看看最近的统一汇总\"}"
      },
      "sender":{"sender_id":{"open_id":"ou_test","user_id":"u_test"}}
    }
  }'
```

注意：

- 上面这条模拟会继续尝试调用飞书发消息接口
- 如果没配 `FEISHU_APP_ID / FEISHU_APP_SECRET`，会返回失败，这属于预期

---

## 6. 当前边界

当前这层故意不做：

- 飞书签名校验
- 飞书加密事件解密
- 去重缓存
- 复杂权限控制
- 富文本卡片

先把最小闭环跑通，再决定是否补这些生产化能力。
