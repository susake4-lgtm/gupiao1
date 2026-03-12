# 朋友 Mac 部署说明

这份文档当前更新为“客户 Mac 可运行版”：

- 在朋友的 Mac 上跑通 `daily_stock_analysis`
- 每天自动生成自选股分析
- 自动推送到飞书
- OpenClaw 可在飞书中响应 `@机器人`

## 1. 你需要先准备好的东西

在迁移到朋友电脑之前，建议先在你自己的电脑验证过一次：

- `./scripts/bootstrap-dsa.sh` 成功
- `./scripts/run-dsa-once.sh --stocks 600519` 成功
- 飞书测试群能收到消息
- `./scripts/run-dsa-schedule.sh` 能稳定运行

## 2. 朋友电脑的基础环境

### 必需软件

- macOS
- Git
- Python 3.10+
- 网络可访问所需模型/搜索服务

### 可选软件

- Node.js 22+（只有以后要跑 OpenClaw 时才需要）

## 3. 拉取仓库

```bash
git clone https://github.com/susake4-lgtm/gupiao1.git
cd gupiao1
```

## 4. 拉取上游并安装依赖

```bash
./scripts/bootstrap-dsa.sh
```

这一步会：

- 拉取 `external/daily_stock_analysis`
- 创建 Python 虚拟环境
- 安装上游依赖

## 5. 准备配置文件

```bash
cp config/dsa.env.example config/dsa.env
cp config/stocks.example config/stocks.md
```

然后编辑 `config/dsa.env`。

### 至少要填的配置

- `OPENAI_API_KEY`
- `FEISHU_WEBHOOK_URL`
- `STOCK_LIST`

当前推荐模型配置口径：

- `OPENAI_BASE_URL=https://ark.cn-beijing.volces.com/api/v3`
- `OPENAI_MODEL=doubao-seed-2-0-pro-260215`
- `LITELLM_MODEL=openai/doubao-seed-2-0-pro-260215`

如果你更习惯用文件维护自选股，也可以：

- 把 `config/dsa.env` 里的 `STOCK_LIST` 留空
- 直接编辑 `config/stocks.md`

## 6. 单次运行验证

先做一次不发通知测试：

```bash
./scripts/run-dsa-once.sh --stocks 600519
```

如果成功，再做一次带推送测试：

```bash
./scripts/run-dsa-once.sh --single-notify
```

如果你只想让它按默认配置跑一次，也可以：

```bash
./scripts/run-dsa-once.sh
```

## 7. 飞书验证

确认下面几件事：

1. 飞书群机器人已经创建
2. `FEISHU_WEBHOOK_URL` 填写正确
3. 运行带通知的命令后，群里能收到消息
4. 消息内容达到“朋友可读”的标准

## 8. 定时运行

本地前台验证：

```bash
./scripts/run-dsa-schedule.sh
```

如果只是先验证，可临时把 `config/dsa.env` 里的：

- `SCHEDULE_ENABLED=true`
- `SCHEDULE_TIME=18:00`

改成更接近当前时间的值，观察一次自动执行。

## 9. 建议的长期运行方式

### 方案 A：朋友电脑常开

如果朋友电脑基本常开，可以直接长期运行：

```bash
./scripts/run-dsa-schedule.sh
```

优点：

- 最直观
- 和本地调试一致
- 后续接 OpenClaw 也方便

### 方案 B：后续迁移到 GitHub Actions

如果朋友电脑不常开，后续可以再把这套配置迁到 GitHub Actions。

上游已经自带工作流参考：

- `external/daily_stock_analysis/.github/workflows/daily_analysis.yml:1`

但这不是当前第一阶段的前置条件。

## 10. OpenClaw 与飞书

如果客户要在飞书群里直接 `@机器人`，还需要：

```bash
bash scripts/start-volcengine-compat-proxy.sh
bash scripts/start-openclaw.sh
```

建议先在你的机器上完成飞书官方插件安装，再迁移到客户机器。

## 11. 客户机器建议启动方式

推荐直接使用一键脚本：

```bash
bash scripts/start-client-stack.sh --with-bridge --with-dsa-api
```

详细说明见：

- [customer-mac-runtime.md](/Users/apple/xinxisouji/gupiao1/docs/customer-mac-runtime.md)
- [openclaw-local-deployment-plan.md](/Users/apple/xinxisouji/gupiao1/docs/openclaw-local-deployment-plan.md)

## 12. 常见问题

### 1) 脚本提示找不到 `external/daily_stock_analysis`

先执行：

```bash
./scripts/bootstrap-dsa.sh
```

### 2) 脚本提示找不到 `openclaw`

说明还没安装 OpenClaw。先执行：

```bash
npm install -g openclaw@latest
```

### 3) 单次运行成功，但飞书没收到

优先检查：

- `FEISHU_WEBHOOK_URL` 是否正确
- 飞书机器人是否仍在群里
- 是否被群机器人安全策略拦住

### 4) 模型调用失败

优先检查：

- API Key 是否有效
- 当前网络是否能访问火山方舟
- 是否需要代理
- `USE_PROXY` / `PROXY_HOST` / `PROXY_PORT` 是否正确
- `curl http://127.0.0.1:19090/health` 是否正常

## 13. 迁移完成标准

满足下面这些，就算朋友版第一阶段可交付：

1. 每天能收到一份自选股分析
2. 你不需要每天手工干预
3. 换一台 Mac 能按文档重复部署
4. 飞书里 `@机器人` 可正常响应
