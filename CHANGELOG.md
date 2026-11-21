# Changelog

本项目遵循「版本号写进 `VERSION`、`SKILL.md` metadata、`evals.json` 三处必须一致」的约定。
发布流程见 [RELEASE.md](RELEASE.md)。

## V1.8.1 — 离线语音闭环（不接 API、不要 Key）

- 新增 `grow-me/scripts/voice-offline.ps1`：Windows SAPI 离线语音壳——麦克风 → 离线识别(zh-CN) → 本地引擎 → 离线合成(zh-CN)；
  `-Text "..." -SaveWav x.wav` 只合成留证，`-Loop` 连续对话，`-EngineUrl`/`-Seconds` 可调；全程不联网、不调 API。
- 本机实测：TTS=`Microsoft Huihui Desktop`(zh-CN)，识别器=`MS-2052-80-DESK`(zh-CN)，合成 WAV 7.0 秒。
- `references/livekit-agents.md` 增「离线语音（不接 API、不要 Key）」；SKILL 第 10 节补一行命令；边界更新。

## V1.8.0 — 实时语音 Agent（vendor LiveKit Agents + 本地等价运行时）

- vendor 上游 `livekit/agents` 核心包与语音示例（Apache-2.0）：`grow-me/vendor/livekit-agents/`，`SOURCE.md` 记录来源与 HEAD `d78f399…`，保留 `LICENSE`/`NOTICE`/`MODEL_LICENSE`。
- 新增 `grow-me/scripts/voice-agent.mjs`：零依赖、无需 LiveKit 服务器的能力等价实现——AgentSession 生命周期、轮次检测、打断(barge-in)、工具调用、插件化 STT/LLM/TTS（离线回退 + OpenAI 兼容）、事件钩子、转写与延迟指标、HTTP/SSE 服务（`demo` / `run` / `serve`）。
- 新增 `grow-me/references/livekit-agents.md`：能力映射表、快速开始、上游生产级用法、明确边界（WebRTC/SIP/电话不复刻）。
- `SKILL.md` 新增第 10 节「能力模块」并补自检项；README 增至十条规则。
- 实测：`demo` 触发 `lookup_faq` 工具；`serve` 接口 `health/turn/transcript/events/interrupt` 全通，打断后下一轮正常。

## V1.7.1 — 定位仪区分「使用技能 / 仅绑定」

- `beacon.mjs register` 新增 `--skill-used true|false`：显式声明该 AI 是否真的在用技能工作。
- 监测台「定位仪」面板新增「用法」列：使用技能（绿）/ 仅绑定（黄）/ 未上报（灰）。
- 起因：A/B 对照实验里 Agent B 只绑定控制台、不读技能，但 beacon 仍会自动读取本机安装版本，
  导致两个 agent 都显示"持证"；加字段后可区分"机器装了技能"与"这个 AI 真的在用技能"。
- 同场实测：A（带 skill）与 B（无 skill）在 10 项裁判检查中均 10/10；A 多出工作记录/日志/9 个测试，
  但自报 tokens 64k vs B 10k。

## V1.7.0 — 说谎程度 + 上下文/token 浪费实时监测

- 定位仪新增 `telemetry`：累计 tokens、浪费 tokens、上下文已用/上限、工具调用、重复读/重复跑/超大输出。
- 监测台新增「实时消耗 / 说谎程度」面板与 `POST/GET /api/telemetry`：
  - **说谎程度** = 未验证声明 ÷ 声明总数（≥30% 标红）
  - **浪费率** = 浪费 tokens ÷ 累计 tokens（≥20% 标红）
  - **上下文占用** = ctx_used ÷ ctx_max（≥85% 标红、65~85% 标黄）
- 头部徽章实时显示全局说谎率 / 浪费率；每个 agent 显示上下文进度条、重复读/重复跑/超大输出计数与标记。
- 实测：win-a（持证）说谎 50%、浪费 7%、ctx 71%；win-waste 浪费 42%、ctx 95% → 标红"上下文将满/浪费高"。

## V1.6.0 — 只读监测台 + 定位仪 + 持证上岗

- 规则九改为**只读监测**：明确"不控制任何 AI"，只观察"谁在线、它的话有多少条有证据"。
- 新增 `grow-me/scripts/beacon.mjs`「定位仪」：报到（register）/心跳（beat、watch）/声明上报（claim）；
  监测台按心跳判在线、按 `skill_version` 判**持证/未持证**、按 claim 统计证据通过率。
- 监测台新增 `/api/beacon`、`/api/agents` 与「定位仪」面板；证据台账按 agent 归属统计。
- **持证才干活**：装了 grow-me 且版本一致 = 持证；未持证标红，不得代表 skill 交付。
- 实测：定位仪报到（持证 V1.6.0）/ 未持证模拟（rogue-ai → 红）/ 一条真证据 + 一条无证据（1 已核验 / 1 未验证）。

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
