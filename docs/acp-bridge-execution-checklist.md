# ACP Bridge 分步实施清单（小步执行版）

- 日期：2026-03-12
- 适用项目：`gupiao1`
- 配套总文档：`docs/acp-bridge-implementation.md`
- 用途：把大任务拆成**可以一条条落地的小步骤**，每次只做一个小目标

---

## 0. 实施原则

这次不再一口气打通整条链路。

改成下面这种方式：

1. 先写清楚当前这一步要做什么
2. 只改少量文件
3. 做完立刻验证
4. 验证通过后再进入下一步

一句话：

> 先把桥一段一段搭起来，不再一次跨太大。

---

## 1. 总目标

最终还是要做到两条线：

### 1.1 查询线

```text
飞书 / OpenClaw
    -> OpenClaw
    -> 现有脚本 / API / 输出文件
    -> 返回 unified / stock / futures / news / health 结果
```

### 1.2 修改线

```text
飞书 / OpenClaw
    -> OpenClaw
    -> acp-bridge
    -> Claude Code
    -> 修改 gupiao1 项目
```

但是现在执行时，按小步骤推进，不直接同时做完两条线。

---

## 2. 分步执行顺序

## Step 1：只补 bridge 启动能力

### 本步目标

只做一件事：

> 让 `acp-bridge` 可以在本机启动，并且配置固定到当前项目。

### 本步只允许改动

- `scripts/start-acp-bridge.sh`
- `config/acp-bridge.env.example`
- `config/acp-bridge.env`

### 本步要求

1. bridge 能启动
2. host 固定为 `127.0.0.1`
3. allowed_ips 包含 `127.0.0.1`
4. 有 bearer token
5. Claude Code 工作目录固定到：

```text
/Users/apple/xinxisouji/gupiao1
```

### 本步验证

至少验证：

- `bash -n scripts/start-acp-bridge.sh`
- 启动后 `/health` 可访问
- agent 配置能被 bridge 读到

### 本步完成标准

- bridge 本地能起来
- 配置文件已落地
- 工作目录约束已写死到配置中

---

## Step 2：只补 OpenClaw -> bridge 提交脚本

### 本步目标

只做一件事：

> 让 OpenClaw 侧有一个统一脚本，专门把 modify/create 请求提交给 `acp-bridge`。

### 本步只允许改动

- `scripts/openclaw-acp-bridge-submit.sh`

### 本步要求

1. 能传入 `modify` / `create`
2. 能传入自然语言任务
3. 能附带 request_id / source / workdir
4. 返回统一结构，至少包含：
   - `status`
   - `summary`
   - `request_id`
   - `raw_tail`

### 本步验证

至少验证：

- `bash -n scripts/openclaw-acp-bridge-submit.sh`
- 手工提交一条最小任务到 bridge
- 能拿到 bridge 返回

### 本步完成标准

- OpenClaw 侧已有稳定 submit wrapper
- modify/create 不再直接散落调用

---

## Step 3：只补最上层路由脚本

### 本步目标

只做一件事：

> 增加一个总路由层，把 query/explain/trigger 和 modify/create 分开。

### 本步只允许改动

- `scripts/openclaw-router.sh`

### 本步要求

支持 5 类动作：

1. `query`
2. `explain`
3. `trigger`
4. `modify`
5. `create`

其中：

- `query|explain|trigger` 继续走现有脚本
- `modify|create` 走 `openclaw-acp-bridge-submit.sh`

### 本步验证

至少验证：

- `bash -n scripts/openclaw-router.sh`
- router 能把 `modify` 分流到 bridge submit
- router 能把 `query` 分流到查询入口

### 本步完成标准

- 项目有统一总入口
- 查询线和修改线正式分开

---

## Step 4：只补查询入口脚本

### 本步目标

只做一件事：

> 新增一个专门的 query/explain 脚本，优先复用现有结果，不默认走 Claude Code。

### 本步只允许改动

- `scripts/openclaw-query-entry.sh`

### 本步要求

至少支持下面这些目标：

1. `unified`
2. `health`
3. `futures`
4. `stock`
5. `news`

优先级要求：

- 先读已有输出文件
- 再调已有脚本/API
- 除非明确是修改请求，否则不要走 bridge

### 本步验证

至少验证：

- `bash -n scripts/openclaw-query-entry.sh`
- `query unified`
- `query health`
- `query futures a0`
- `explain unified latest`

### 本步完成标准

- 查询线已能覆盖核心结果
- explain 也可以基于已有结果工作

---

## Step 5：只补文档和 env 约定

### 本步目标

只做一件事：

> 把桥接层和双入口的使用方式写清楚，不再混在旧文档里。

### 本步只允许改动

- `docs/acp-bridge-implementation.md`
- `docs/openclaw-local-deployment-plan.md`
- `docs/env-unification-reference.md`
- 新增 `docs/feishu-openclaw-acp-bridge.md`

### 本步要求

写清楚：

1. bridge 怎么启动
2. OpenClaw 怎么调用 bridge
3. 飞书怎么接 OpenClaw
4. bridge env 和业务 env 分离
5. TrendRadar 端口统一写成 `3334`

### 本步验证

至少检查：

- 文档中的端口不再混乱
- bridge env 不写进 `dsa.env`
- 本机入口和飞书入口说明一致

### 本步完成标准

- 文档足够让后续系统继续执行
- env 契约清楚

---

## Step 6：只做本机入口联调

### 本步目标

只做一件事：

> 先不管飞书，先把本机 OpenClaw 入口打通。

### 本步要求

从本机入口验证下面几条：

1. `query recent unified`
2. `query today health`
3. `query today futures a0`
4. `explain latest unified`
5. `modify <一条最小修改任务>`

### 本步完成标准

- 本机 OpenClaw 已能查结果
- 本机 OpenClaw 已能通过 bridge 触发 Claude Code

---

## Step 7：只做飞书入口联调

### 本步目标

只做一件事：

> 把飞书作为薄入口接到已经完成的 OpenClaw 路由层上。

### 本步要求

1. 飞书消息进入 OpenClaw
2. OpenClaw 复用同一套路由脚本
3. 返回结构和本机入口尽量一致

### 本步验证

至少验证：

- 飞书发一条查询消息
- 飞书发一条修改消息
- OpenClaw 返回结果到飞书

### 本步完成标准

- 飞书只是入口适配层
- 核心逻辑仍在 repo 内脚本里

---

## Step 8：做最终回归

### 本步目标

只做一件事：

> 用最少但真实的样例，把两条主链路都跑通一遍。

### 回归清单

#### 查询线

1. 最近一次 unified
2. 今天四模块健康状态
3. 今日 a0 期货汇总
4. 今日股票汇总
5. 今日新闻汇总
6. 解释最近一次 unified

#### 修改线

1. 修改一个配置文件
2. 修改一个脚本或模板
3. 新增一个小文件

### 本步完成标准

- 查询线有真实成功样例
- 修改线有真实成功样例
- 本机入口和飞书入口都能复用同一套路由

---

## 3. 现在的执行方式

从现在开始，按下面节奏推进：

1. 先完成 Step 1
2. Step 1 验证通过后，再做 Step 2
3. 不跨步，不并大步
4. 每步做完都记录：
   - 改了哪些文件
   - 怎么验证的
   - 下一步是什么

---

## 4. 当前建议立即开始的步骤

当前先做：

> **Step 1：只补 bridge 启动能力**

也就是先落地：

- `scripts/start-acp-bridge.sh`
- `config/acp-bridge.env.example`
- `config/acp-bridge.env`

先把 bridge 起起来，再继续后面的 submit / router / query。

---

## 5. 一句话结论

> 现在不再整包推进，而是拆成 8 个小步骤；每次只做一步，先把 `acp-bridge` 启动层落地，再一层层往上接 OpenClaw、查询路由和飞书入口。
