# OpenClaw 本机部署与双链路说明（gupiao1 项目版）

## 1. 当前定位

OpenClaw 在本项目中的定位仍然是：**控制层 / 交互层**。

它不接管股票、期货、新闻的核心业务实现，也不接管每日主调度；它负责把用户输入分流到已经存在的仓库脚本与桥接层。

当前本机入口有两条线：

1. **查询线**：`query|explain`
   - 优先复用本地产物、现有脚本、现有 API
   - 默认不走 bridge
2. **修改线**：`modify|create`
   - 统一走 `OpenClaw -> acp-bridge -> Claude Code`

补充：

3. **模型兼容层**
   - 当前 OpenClaw 默认通过本地 Volcengine 兼容代理访问火山
   - 代理负责删除火山不支持的字段（当前已确认包括 `prompt_cache_key`）

---

## 2. 端口与脚本约定

### 2.1 OpenClaw 本机启动

项目内已封装启动脚本：

- 启动脚本：`scripts/start-openclaw.sh`
- 默认 bind：`loopback`
- 默认端口：`127.0.0.1:18789`
- bind 变量：`OPENCLAW_BIND`
- 端口变量：`OPENCLAW_PORT`
- 当前脚本从 `config/dsa.env` 读取 `OPENCLAW_BIND` / `OPENCLAW_PORT`

这属于**当前脚本实现细节**，不表示 OpenClaw 已经有独立 env 层，也不表示该变量属于 bridge env。

见：

- `scripts/start-openclaw.sh:4`
- `scripts/start-openclaw.sh:12`
- `scripts/start-openclaw.sh:21`

### 2.2 当前统一口径端口

当前相关链路端口统一理解为：

- OpenClaw Gateway：`18789`
- DSA API：`8000`
- Futures API：`8010`
- TrendRadar：`3334`
- ACP Bridge：默认示例为 `8001`
- Volcengine 兼容代理：`19090`

注意：

- 旧文档中可能仍残留 TrendRadar `3333`
- 当前 Step 5 文档口径统一改为 `3334`
- 若未来脚本、健康检查、本机运行事实与文档再次冲突，应先以运行事实为准，再更新文档

---

## 3. 本机入口的统一路由层

当前本机应优先复用统一路由脚本：

- `scripts/openclaw-router.sh`

路由规则已经固定为：

- `query|explain` -> `scripts/openclaw-query-entry.sh`
  - 若该文件不存在，才 fallback 到 `scripts/openclaw-unified-entry.sh`
- `trigger` -> `scripts/openclaw-unified-entry.sh`
- `modify|create` -> `scripts/openclaw-acp-bridge-submit.sh`

见：

- `scripts/openclaw-router.sh:11`
- `scripts/openclaw-router.sh:58`
- `scripts/openclaw-router.sh:65`

也就是说：

> 本机入口不应该再各写一套 query / modify 分流逻辑，而应统一复用 `scripts/openclaw-router.sh`。

---

## 4. 查询线怎么工作

查询线由下面这条路径完成：

```text
本机用户
    -> OpenClaw / 本机命令
    -> scripts/openclaw-router.sh
    -> query|explain
    -> scripts/openclaw-query-entry.sh
    -> 现有输出文件 / 现有脚本 / 现有 API
```

当前查询入口的原则：

1. 优先读现有 unified 报告与现有产物
2. 再读现有 health 脚本或 futures API
3. 找不到结果时返回清晰提示
4. 不触发新的 once-run
5. 默认不走 bridge

当前已覆盖目标：

- `unified`
- `health`
- `futures`
- `stock`
- `news`

---

## 5. 修改线怎么工作

修改线由下面这条路径完成：

```text
本机用户
    -> OpenClaw / 本机命令
    -> scripts/openclaw-router.sh
    -> modify|create
    -> scripts/openclaw-acp-bridge-submit.sh
    -> ACP Bridge /runs
    -> Claude Code
    -> 修改 gupiao1 仓库
```

这里要点是：

- bridge 启动入口是 `scripts/start-acp-bridge.sh`
- bridge 配置来源是 `config/acp-bridge.env`
- Claude Code 工作目录由 `ACP_BRIDGE_WORKDIR` 控制，当前默认应指向仓库根目录
- 查询线与修改线共享同一个 router，但不共享同一种执行方式

---

## 6. 本机部署步骤（Mac）

> 以下步骤按“本机入口优先”理解，不展开飞书联调。

### 6.1 安装 OpenClaw CLI

```bash
npm install -g openclaw@latest
```

### 6.2 启动 OpenClaw

在项目根目录执行：

```bash
bash scripts/start-volcengine-compat-proxy.sh
bash scripts/start-openclaw.sh
```

脚本会：

1. 先启动本地 Volcengine 兼容代理
2. OpenClaw 再连接本地代理后的 Volcengine 模型
3. 使用 `OPENCLAW_BIND`（若未设置则默认 `loopback`）
4. 使用 `OPENCLAW_PORT`（若未设置则默认 `18789`）
5. 执行 `openclaw gateway --bind <BIND> --port <PORT> --verbose`

### 6.3 如需修改项目能力，再启动 bridge

```bash
bash scripts/start-acp-bridge.sh
```

这一步不是查询线前置条件；它是**修改线前置条件**。

---

## 7. 本机最小使用示例

### 7.1 查询 unified

```bash
bash scripts/openclaw-router.sh query unified recent
```

### 7.2 查询四模块健康

```bash
bash scripts/openclaw-router.sh query health today
```

### 7.3 查询 futures

```bash
bash scripts/openclaw-router.sh query futures a0
```

### 7.4 查询 stock

```bash
bash scripts/openclaw-router.sh query stock today
```

### 7.5 查询 news

```bash
bash scripts/openclaw-router.sh query news today
```

### 7.6 解释 unified

```bash
bash scripts/openclaw-router.sh explain unified latest
```

### 7.7 提交修改任务

```bash
bash scripts/openclaw-router.sh modify "把 futures 的输出模板改一下"
```

---

## 8. 本机并行运行建议

### Terminal A：OpenClaw

```bash
cd /Users/apple/xinxisouji/gupiao1
bash scripts/start-volcengine-compat-proxy.sh
```

### Terminal B：OpenClaw

```bash
cd /Users/apple/xinxisouji/gupiao1
./scripts/start-openclaw.sh
```

### Terminal C：ACP Bridge（仅修改线需要）

```bash
cd /Users/apple/xinxisouji/gupiao1
bash scripts/start-acp-bridge.sh
```

### Terminal D：需要时再启动业务侧服务

按实际联调目标启动：

- DSA API
- Futures API
- TrendRadar

其中 TrendRadar 当前文档口径统一按 `3334` 理解。

---

## 9. 常见问题

### 9.1 `openclaw command not found`

说明 OpenClaw CLI 未安装或 PATH 未生效。先执行：

```bash
npm install -g openclaw@latest
```

### 9.2 18789 端口被占用

处理方式：

- 修改 `config/dsa.env` 中 `OPENCLAW_PORT`
- 或先释放占用端口

### 9.3 查询能用，但修改不通

优先检查：

- `scripts/start-acp-bridge.sh` 是否已启动
- `config/acp-bridge.env` 是否已配置 token / host / port / workdir
- `external/acp-bridge` 与本机 Claude CLI 是否可用

### 9.4 修改能发出，但不是在当前仓库生效

优先检查：

- `ACP_BRIDGE_WORKDIR` 是否仍指向 `/Users/apple/xinxisouji/gupiao1`

---

## 10. 与后续飞书入口的关系

后续飞书接入时，应复用与本机相同的路由层，而不是在飞书侧重写业务逻辑。

目标关系应为：

```text
飞书消息
    -> OpenClaw
    -> scripts/openclaw-router.sh
    -> query|explain|trigger|modify|create 分流
```

也就是说：

- 本机入口与飞书入口共享同一个 router
- 查询线共享同一个 `scripts/openclaw-query-entry.sh`
- 修改线共享同一个 `scripts/openclaw-acp-bridge-submit.sh`

---

## 11. 一句话结论

> 当前本机 OpenClaw 入口已经明确分成两条线：`query|explain` 走本地查询入口，`modify|create` 走 bridge 写入入口；两条线统一复用 `scripts/openclaw-router.sh`，TrendRadar 当前文档口径统一为 `3334`。
