# ACP Bridge / OpenClaw 续做计划（重启 Claude Code 用）

- 日期：2026-03-12
- 项目：`gupiao1`
- 用途：重启 Claude Code 后，直接按这个文件继续做，不用重新梳理上下文

---

## 1. 当前目标

当前仍然按“小步执行”推进，只做桥接层和路由层，不一次性做完整大集成。

总目标不变：

1. `query|explain|trigger` 优先复用仓库现有脚本、输出文件、API
2. `modify|create` 统一走 `OpenClaw -> acp-bridge -> Claude Code`
3. 让本机 OpenClaw 与后续飞书入口都复用同一套路由

---

## 2. 已完成步骤

### Step 1：bridge 启动层

已完成文件：

- `scripts/start-acp-bridge.sh`
- `config/acp-bridge.env.example`
- `config/acp-bridge.env`

已确认：

- bridge 监听本机 `127.0.0.1`
- `allowed_ips` 包含 `127.0.0.1`
- bearer token 已配置
- Claude Code 工作目录固定到：

```text
/Users/apple/xinxisouji/gupiao1
```

已验证：

- `bash -n scripts/start-acp-bridge.sh`
- `/health` 可访问
- `/health/agents` 可访问

### Step 2：OpenClaw -> bridge submit wrapper

已完成文件：

- `scripts/openclaw-acp-bridge-submit.sh`

当前能力：

- 支持 `modify|create`
- 支持自然语言指令
- 支持 `--source`
- 支持 `--request-id`
- 支持 `--session`
- 支持 `--timeout`
- 支持 `--url`
- 返回统一 JSON 结构：
  - `status`
  - `summary`
  - `request_id`
  - `raw_tail`
  - `session_id`

本步已修正的问题：

- `session_id` 不能直接复用普通字符串 `request_id`
- 现已改为默认生成合法 UUID

已验证：

- `bash -n scripts/openclaw-acp-bridge-submit.sh`
- 最小 modify 请求可成功提交到 bridge
- 能拿到标准化返回

### Step 3：最上层路由脚本

已完成文件：

- `scripts/openclaw-router.sh`

当前路由规则：

- `query|explain`：
  - 若存在 `scripts/openclaw-query-entry.sh`，优先走它
  - 否则先回退到 `scripts/openclaw-unified-entry.sh`
- `trigger`：继续走 `scripts/openclaw-unified-entry.sh`
- `modify|create`：走 `scripts/openclaw-acp-bridge-submit.sh`

已验证：

- `bash -n scripts/openclaw-router.sh`
- `scripts/openclaw-router.sh query recent`
- `scripts/openclaw-router.sh modify "..."` 能转发到 bridge submit

补充说明：

- 路由脚本已加可执行权限
- Step 4 完成后，`query|explain` 会自然切到新的 query entry，无需重写 router

---

## 3. 下一步只做什么

下一步只做：

> **Step 4：只补查询入口脚本**

目标：

新增：

- `scripts/openclaw-query-entry.sh`

要求：

至少支持下面这些目标：

1. `unified`
2. `health`
3. `futures`
4. `stock`
5. `news`

优先级：

1. 先读已有输出文件
2. 再调已有脚本/API
3. 除非明确是修改请求，否则不要走 bridge

---

## 4. Step 4 建议实现方式

### 4.1 输入形式

建议支持：

```text
scripts/openclaw-query-entry.sh query unified recent
scripts/openclaw-query-entry.sh query health today
scripts/openclaw-query-entry.sh query futures a0
scripts/openclaw-query-entry.sh query stock today
scripts/openclaw-query-entry.sh query news today
scripts/openclaw-query-entry.sh explain unified latest
scripts/openclaw-query-entry.sh explain futures a0
```

### 4.2 路由建议

#### unified

直接复用：

- `scripts/openclaw-unified-entry.sh`

#### health

直接复用：

- `scripts/check-four-modules-health.sh`

#### futures

优先读：

- `data/futures/report_<symbol>.md`
- `data/futures/latest_<symbol>.json`

必要时再考虑：

- futures 现有 API / 脚本

#### stock

优先复用：

- DSA 已有输出
- unified 中已有股票段落
- 现有 API / 日志

#### news

优先复用：

- TrendRadar 已有输出
- unified 中已有 news 段落
- 现有输出目录 / 元数据

---

## 5. Step 4 最低验证清单

至少做：

- `bash -n scripts/openclaw-query-entry.sh`
- `bash scripts/openclaw-query-entry.sh query unified recent`
- `bash scripts/openclaw-query-entry.sh query health today`
- `bash scripts/openclaw-query-entry.sh query futures a0`
- `bash scripts/openclaw-query-entry.sh explain unified latest`
- `bash scripts/openclaw-router.sh query unified recent`

通过标准：

- router 的 `query|explain` 已能接到新 query entry
- 查询默认不走 bridge
- 至少 unified / health / futures 能给出真实可读结果

---

## 6. 当前涉及的关键文件

已完成：

- `scripts/start-acp-bridge.sh`
- `scripts/openclaw-acp-bridge-submit.sh`
- `scripts/openclaw-router.sh`
- `config/acp-bridge.env.example`
- `config/acp-bridge.env`
- `docs/acp-bridge-execution-checklist.md`

下一步重点读：

- `scripts/openclaw-unified-entry.sh`
- `scripts/check-four-modules-health.sh`
- `scripts/run-futures-briefing-once.sh`
- `scripts/run-dsa-once.sh`
- `scripts/run-trendradar-once.sh`
- `docs/acp-bridge-execution-checklist.md`

---

## 7. 重启后一句话执行指令

重启 Claude Code 后，直接从这里继续：

> 继续做 Step 4，只实现 `scripts/openclaw-query-entry.sh`，优先复用现有输出和脚本，不要改 Step 1/2/3 已完成内容；做完后按本文件里的验证清单验证。
