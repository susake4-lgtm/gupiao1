# gupiao1 Agent Guide

适用于本仓库内执行任务的 Codex / Claude Code / 其他可读取仓库规则文件的代理。

## Goal

本仓库默认目标不是做一次性大改，而是在既有四个子项目和桥接层上做小步、可验证、可回滚的优化。

## Read Order

开始任何非闲聊任务前，按下面顺序读取：

1. [CLAUDE.md](CLAUDE.md)
2. [README.md](README.md)
3. [./.claude/rules/README.md](./.claude/rules/README.md)
4. 只读取当前任务直接相关的规则文件

## Project Boundaries

默认先按子项目边界处理任务：

- `股票 / DSA`
- `期货 / Futures`
- `新闻 / TrendRadar`
- `OpenClaw`
- `ACP Bridge / Claude Code`

除非任务明确要求或问题跨模块成因明确，不要把单模块修复扩成跨模块改造。

## Execution Rules

- 先定义本次 milestone，再动手修改。
- 先复用已有脚本、配置、文档和上游能力，再考虑新增实现。
- 能只改一层就不要跨层联动。
- 能只验一个模块就不要先跑全仓回归。
- 涉及脚本、配置、接口或输出约定变更时，同步更新相关文档。
- 不把本机全局 `~/.claude` 当成唯一依赖；长期规则必须落在仓库内。

## Rule Sources

本仓库内规则分两层：

1. 项目入口与操作边界：`CLAUDE.md`
2. 更细粒度约束：`./.claude/rules/*.md`

如果与上层运行时指令不冲突，应优先遵守仓库内规则。

## Available Skills

以下是本仓库内建议优先使用的项目级 skills：

- `gupiao1-task-routing`: 把任务路由到正确子项目、收敛 milestone，并选择最小验证范围。
- `gupiao1-implementation-guardrails`: 约束脚本、配置、文档、桥接层与代码修改的最小实现路径。
- `gupiao1-market-output-discipline`: 约束市场信息、信息源、watchlist、摘要模板与事实边界。

技能文件路径：

- [skills/gupiao1-task-routing/SKILL.md](skills/gupiao1-task-routing/SKILL.md)
- [skills/gupiao1-implementation-guardrails/SKILL.md](skills/gupiao1-implementation-guardrails/SKILL.md)
- [skills/gupiao1-market-output-discipline/SKILL.md](skills/gupiao1-market-output-discipline/SKILL.md)

## How To Use Skills

- 任务一开始先判断是否需要 skill；只加载必要 skill，不要全读。
- skill 负责流程和决策约束，不代替项目文档本身。
- 如果 skill 引用规则文件，只读取当前任务需要的那几份。
- 如果任务同时涉及工程改动和市场内容，先用 `gupiao1-task-routing`，再按需要补充另一个 skill。

## Default Optimization Path

当用户说“优化项目”但没有明确范围时，默认按下面顺序推进：

1. 识别属于哪个子项目或桥接层
2. 发现当前最影响稳定性的单点问题
3. 用最小修改完成一个 milestone
4. 做最接近改动面的验证
5. 更新必要文档
6. 再进入下一个 milestone
