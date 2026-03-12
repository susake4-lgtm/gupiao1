---
name: gupiao1-task-routing
description: Route a user request to the correct gupiao1 subproject, set a minimal milestone, and choose the smallest valid verification scope. Use when a task is ambiguous, spans multiple folders, or could accidentally expand into a cross-module change.
---

# gupiao1 Task Routing

先做路由，再做实现。

## Read First

1. [CLAUDE.md](../../CLAUDE.md)
2. [./.claude/rules/README.md](../../.claude/rules/README.md)
3. 按需读取：
   - [./.claude/rules/01-project-scope.md](../../.claude/rules/01-project-scope.md)
   - [./.claude/rules/04-mvp-boundaries.md](../../.claude/rules/04-mvp-boundaries.md)
   - [./.claude/rules/05-engineering-workflow.md](../../.claude/rules/05-engineering-workflow.md)

## Routing Workflow

1. 先判断任务属于哪个边界：
   - `DSA`：股票分析、日报、股票 API、股票输出
   - `Futures`：期货汇总、期货 API、期货报告
   - `TrendRadar`：新闻、热点、舆情补充
   - `OpenClaw`：查询、解释、手动触发入口
   - `ACP Bridge`：把修改请求路由给代理执行
2. 如果任务看起来跨模块，先判断是不是单模块根因引发的连带现象。
3. 只定义一个当前 milestone，避免一次把多个模块一起重构。
4. 先看改动面附近的文件、脚本、配置和文档，不要先做全仓扫描式大改。

## Default Decisions

- 模糊任务默认按最小边界归类。
- 新闻模块默认是补充链路，不轻易把它当主链路故障。
- OpenClaw 默认是控制层，不接管股票、期货、新闻的核心业务实现。
- Bridge 默认是桥接层，不因为接入代理就重写业务逻辑。

## Verification Map

改哪里，先验哪里：

- `DSA`
  - `bash -n scripts/run-dsa-once.sh`
  - `bash -n scripts/run-dsa-api.sh`
- `Futures`
  - `bash -n scripts/run-futures-briefing-once.sh`
  - `bash -n scripts/run-futures-api.sh`
- `TrendRadar`
  - `bash -n scripts/run-trendradar-once.sh`
- `OpenClaw`
  - `bash -n scripts/start-openclaw.sh`
  - `bash -n scripts/openclaw-unified-entry.sh`
- `ACP Bridge`
  - `bash -n scripts/start-acp-bridge.sh`
  - `bash -n scripts/openclaw-acp-bridge-submit.sh`

## Stop Conditions

出现下面任一情况时，不要继续扩改：

- 当前任务已从单模块滑向跨模块
- 需要改动 `external/` 上游源码才能前进
- 新问题和当前 milestone 不直接相关
- 需要新增依赖但收益不明确
