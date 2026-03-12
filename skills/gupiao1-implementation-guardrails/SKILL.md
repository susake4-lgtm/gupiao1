---
name: gupiao1-implementation-guardrails
description: Apply minimal-scope engineering changes in gupiao1 while preserving module boundaries, reusing existing scripts and upstream components, and running the smallest relevant verification. Use for code, config, script, bridge, and documentation changes.
---

# gupiao1 Implementation Guardrails

## Core Principle

先复用，再修改；先小步落地，再扩大范围。

## Read First

1. [CLAUDE.md](/Users/apple/xinxisouji/gupiao1/CLAUDE.md)
2. [./.claude/rules/05-engineering-workflow.md](/Users/apple/xinxisouji/gupiao1/.claude/rules/05-engineering-workflow.md)
3. 当前改动直接相关的规则文件

## Implementation Rules

- 优先复用现有脚本、env、配置样例、部署说明和目录结构。
- 优先在仓库壳层解决问题，不轻易直接修改 `external/` 下的上游项目。
- 单次任务优先完成一个可交付 milestone，不把“顺手优化”混进同一改动。
- 配置契约变更时，至少同步一个样例文件或文档说明。
- 输出结构变更时，至少同步模板、说明或调用方约定。
- 只有当前项目长期重复需要的能力，才固化为项目级 skill 或规则。

## Preferred Change Order

1. 先定位最小改动点
2. 先改脚本或配置胶水层
3. 再考虑模块内部实现
4. 最后才考虑跨模块联动

## Preferred Validation Order

1. 语法级或静态检查
2. 单脚本最小运行
3. 单模块健康检查
4. 必要时再做跨模块联调

## Documentation Sync

以下改动默认需要看文档是否同步：

- `scripts/`
- `config/`
- `docs/`
- `README.md`
- `CLAUDE.md`
- `./.claude/rules/*.md`

## Anti-Patterns

- 因为“结构更优雅”就重排整个仓库
- 因为接了代理桥接就重写业务主链路
- 因为发现其他问题就扩大当前任务边界
- 还没验证最小链路就先做统一大回归
