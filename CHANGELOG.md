# Changelog

本项目遵循「版本号写进 `VERSION`、`SKILL.md` metadata、`evals.json` 三处必须一致」的约定。
发布流程见 [RELEASE.md](RELEASE.md)。

## V1.5.0 — 接管控制台（端口 8176）

- 规则九「接管与控制台」：接手后立刻起本地控制台（默认 `127.0.0.1:8176`，端口占用自动 +1）、
  扫描本机 AI 并标注哪些装了 grow-me、把"已完成"登记成证据台账（无证据 = 未验证 = 视同说谎）。
- 新增 `grow-me/scripts/console.mjs` + `console.html` + `scan-ai.mjs`：
  Loss 工作台（瞎猜线 8.76、目标区间 2~3、阶段边界）、AI 扫描、证据台账、模型备份清单。
- 新增 `grow-me/references/console.md`、`grow-me/references/minmind-training.md`
  （minmind 预训练：6 阶段 × 3 子阶段、每段 checkpoint、概念解释要求）。
- 红线与自检各补一条"控制台/证据"检查；规则一至八语义不变。

## V1.4.0 — 开源同步 + 发布流程

- 仓库公开：<https://github.com/dl4171503-ll12/Grow-ME>，成为版本发布的**第一落点**。
- 新增 `RELEASE.md` / `scripts/release.ps1`：发布第一步固定为「推送本仓库」，再同步本机安装副本。
- 新增 `CONTRIBUTING.md`、`CHANGELOG.md`、GitHub Actions 自动校验。
- 规则语义不变：仍为八条规则 + 反偷懒/反空转红线。

## V1.3.0 — 多 Agent 总线（Webhook）

- 规则八：`scripts/bus.mjs` 提供 `serve / register / agents / send / inbox / read / ack / pending / nudge / verify / wait`。
- 解决三种信息孤岛：找不到人（心跳注册表）、发了没人看（强制通知）、看了没回执（pending + nudge）。
- 消息五要素、文档只传路径 + sha1 + 摘要、`kind` 白名单、`requires_ack` 默认 30 分钟时限。
- 实测：CLI 全流程、裸 HTTP webhook（UTF-8）、催办、wait 超时、两窗口端到端。

## V1.2.0 — 自动测试轮次

- 规则七：用户说「自动化测试几轮」即放行，执行「提交给自己 → 自审 → 自试 → 择优修复」N 轮（默认 3，最多 5）。
- 硬刹车：用户发来新消息立刻停并落盘；同一 bug 连修 2 轮仍红则上报。
- 新增 `references/auto-rounds.md`、`.grow-me/rounds/` 约定。

## V1.1.0 — 常驻工作模式

- 从"流程技能"改为"常驻协议"：装上即对所有动手类任务生效。
- 规则一 自动落盘（`.grow-me/` 七节记录）、规则二 上下文纪律（不整目录通读、不重读、长输出外置）。
- 新增 `references/context-and-docs.md`、`references/porting.md`。
- 经 1 次自测 + 4 次子 agent 冷启动实验加固（可逆假设、四档开工优先级、记录骨架内联）。

## V1.0.0 — 首个版本

- 追问闸门（设计树 + 前沿轮次）、五维工件、预算化循环、证据收尾。
- 反偷懒红线 5 条 + 反空转红线 5 条 + 自检清单。
- `scripts/validate-skill.mjs`、`evals/evals.json`。
