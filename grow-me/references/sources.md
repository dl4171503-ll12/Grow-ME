# 来源、致谢与版本记录

## 这个 skill 是什么

`grow-me` 是一份**常驻工作协议**，不是工具封装。装上后对所有"动手类"任务生效，做三件事：

1. **先问清**：用设计树前沿轮次把需求追问到不需要猜。
2. **先落盘**：工作状态写进 `.grow-me/` 记录，上下文只留结论 —— 这是省 token 的根基。
3. **再动手**：五维工件 + 预算化循环 + 证据收尾，反偷懒也反空转。

## 术语说明（诚实声明）

`harness engineering`、`graph engineering`、`prompt engineering`、`context engineering`、`loop engineering`
没有统一行业定义，属于围绕 AI agent 工作方式的工作性提法。本 skill 把它们落成可执行动作：

| 提法 | 本 skill 中的落地含义 |
|---|---|
| Harness engineering | 把"可验证"变成硬前提：验证命令清单、最小验证、真实执行证据 |
| Graph engineering | 把任务当 DAG：节点可验证、边是依赖、标并行、按拓扑序推进 |
| Prompt engineering | 每个节点写成可判定规格：目标 / 约束 / 验收 |
| Context engineering | 省上下文：检索优先、不重读、带行号引用、状态外置到记录 |
| Loop engineering | 给循环装刹车：固定五步 + 每节点预算 + 失败升级 + 达标即停 |

## 借鉴的上游

- **grill-me**（设计树 + 前沿轮次 + "事实归自己、决策归用户"）：Matt Pocock 的 `grilling` 思路，
  实现见 `matt-riley/agent-skills` 的 `skills/grill-me` 与 `ksimback/hermes-ecosystem` 的
  `software-development/grill-me`（MIT）。本 skill 的追问协议是其裁剪改写版。
- **skill-creator**（Anthropic 官方）：技能结构、渐进式披露、描述触发原则。
  已安装于 `~/.agents/skills/skill-creator`。
- **create-skill**（本机内置）：Codex 技能目录约定与 frontmatter 规则。

## 版本记录

### V1.8.3（离线神经语音 + 中英混读修音）
- 新增 `scripts/voice-piper-tts.ps1`：Piper 离线神经 TTS（`-Ensure` 自动从 hf-mirror 下模型；`-LengthScale` 调语速）。
- 新增 `scripts/voice-hybrid-tts.ps1`：中英自动分流——中文 `zh_CN-huayan-medium` + 英文 `en_US-lessac-medium`，重采样拼接成单段 22050Hz WAV；修掉 "AI Agent 读成 爱爱进"。
- `scripts/voice-offline.ps1` 默认引擎改为 `hybrid`（回退 piper→winrt→sapi）。
- 模型缓存在 `%USERPROFILE%\.grow-me\tts\piper`（两个 ~63MB，不入技能包）；安装：`py -3 -m pip install piper-tts`。
- 实测：同一句 118KB / 2.9s，中文段 huayan、英文段 lessac。

### V1.8.2（换更好听的离线声音：WinRT 自然语音）
- 新增 `scripts/voice-winrt-tts.ps1`：用 WinRT `Windows.Media.SpeechSynthesis` 调 Windows 自然语音（比 SAPI 好听），支持 `-ListVoices`、`-Voice`、`-SaveWav`、`-Rate`、`-NoPlay`。
- `scripts/voice-offline.ps1` 默认改用 **Microsoft Yaoyao** 自然女声（`-Voice "Microsoft Kangkang"` 换男声；`-TtsEngine sapi` 可回退）。
- 本机可用：Yaoyao(女)/Kangkang(男)/Huihui(女) zh-CN；Tracy zh-HK；Hanhan/Yating/Zhiwei zh-TW。
- 实测：同一句「你好，我是一个 AI Agent」三个声音 WAV（Huihui 105KB/3.3s、Yaoyao 91KB/2.9s、Kangkang 88KB/2.8s）。

### V1.8.1（离线语音闭环：不接 API 也能开口）
- 新增 `scripts/voice-offline.ps1`：Windows SAPI 离线语音壳——麦克风 → 离线识别(zh-CN) → 本地引擎 → 离线合成(zh-CN)；
  支持 `-Text` 合成留证（`-SaveWav`）、`-Loop` 连续对话、`-EngineUrl`/`-Seconds` 参数；全程不联网、不要 API Key。
- 本机实测：TTS=`Microsoft Huihui Desktop`(zh-CN)，识别器=`MS-2052-80-DESK`(zh-CN)，合成 WAV 7.0 秒可回放。
- 文档：`references/livekit-agents.md` 增「离线语音（不接 API、不要 Key）」；SKILL 第 10 节补一行命令；边界更新。

### V1.8.0（实时语音 Agent：vendor LiveKit Agents + 本地等价运行时）
- vendor 上游 `livekit/agents` 核心包与语音示例（Apache-2.0，`vendor/livekit-agents/`，`SOURCE.md` 记录 HEAD `d78f399…`）。
- 新增 `scripts/voice-agent.mjs`：零依赖、无需 LiveKit 服务器的能力等价实现——AgentSession 生命周期、
  轮次检测、打断、工具调用、插件化 STT/LLM/TTS（离线回退 + OpenAI 兼容）、事件钩子、转写与延迟指标、HTTP/SSE 服务。
- 新增 `references/livekit-agents.md`：能力映射表、快速开始、上游生产级用法、明确边界（WebRTC/SIP/电话不复刻）。
- SKILL.md 新增第 10 节「能力模块」，自检补语音模块检查。

### V1.7.1（定位仪区分"使用技能 / 仅绑定"）
- 定位仪 `register` 新增 `--skill-used true|false`：显式声明这个 AI 是不是真的在用技能工作。
- 监测台定位仪表格新增「用法」列：`使用技能`（绿）/ `仅绑定`（黄）/ `未上报`（灰）。
- 背景：A/B 对照实验里，Agent B 只绑定控制台、不读技能，但 beacon 仍会自动读到本机安装版本，
  导致两者都显示"持证"。加这个字段后能区分"机器装了技能"与"这个 AI 真的在用技能"。

### V1.7.0（说谎程度 + 上下文/token 浪费实时监测）
- 定位仪新增 `telemetry` 上报：累计 tokens、浪费 tokens、上下文已用/上限、工具调用数、重复读/重复跑/超大输出。
- 监测台新增 `POST /api/telemetry` 与「实时消耗 / 说谎程度」面板：
  **说谎程度** = 未验证声明占比；**浪费率** = 浪费 tokens ÷ 累计 tokens；
  上下文占用 ≥85%、浪费率 ≥20%、说谎率 ≥30% 分别标红/黄告警。
- 头部徽章实时显示全局说谎率/浪费率；每个 agent 显示上下文进度条与标记。
- 规则九补第 5 条：每 ~10 次工具调用或每 5 分钟上报一次 telemetry。

### V1.6.0（只读监测台 + 定位仪 + 持证上岗）
- 规则九改为**只读监测**：明确"不控制任何 AI"，只观察"谁在线、它的话有多少条有证据"。
- 新增 `scripts/beacon.mjs`「定位仪」：AI 报到（register）/心跳（beat/watch）/声明上报（claim），
  心跳超时判离线，`skill_version` 判**持证/未持证**。
- 监测台新增 `/api/beacon`、`/api/agents` 与"定位仪"面板；证据台账按 agent 归属统计。
- **持证才干活**：装了 grow-me 且版本一致 = 持证；未持证标红，不得代表 skill 交付。

### V1.5.0（接管控制台 + 端口 8176）
- 规则九「接管与控制台」：接手后立刻起本地控制台（默认 `127.0.0.1:8176`，占用自动 +1）、扫描本机 AI、
  把"已完成"登记成 证据台账（无证据 = 未验证 = 视同说谎）。
- 新增 `scripts/console.mjs` + `scripts/console.html` + `scripts/scan-ai.mjs`：
  Loss 工作台（瞎猜线 8.76 / 目标区间 2~3）、AI 与技能安装扫描、证据台账、模型备份清单。
- 新增 `references/console.md`、`references/minmind-training.md`（6 阶段 × 3 子阶段、checkpoint、
  概念解释要求）。
- 规则一至八语义不变；红线与自检各补一条"控制台/证据"检查。

### V1.4.0（开源同步 + 发布流程）
- 仓库：`https://github.com/dl4171503-ll12/Grow-ME`（公开），本 skill 的版本发布以此仓库为**第一落点**。
- 新增 `RELEASE.md` / `scripts/release.ps1`：发布清单固定为「改版本号 → 跑校验 → 提交打 tag → **先推仓库** → 再更新本机安装副本」。
- 新增 `CONTRIBUTING.md`（共创规范）、`CHANGELOG.md`、GitHub Actions 自动校验（`scripts/validate-skill.mjs`）。
- 规则内容不变（V1.3.0 的八条规则与红线保持原样）。

### V1.3.0（新增多 Agent 总线）
- 规则八「多 Agent 总线（Webhook）」：本地 HTTP 服务 + 文件邮箱，`send/inbox/read/ack/pending/nudge/agents/wait` 八个动作。
- 解决三种信息孤岛：找不到人（`agents` 心跳）、发了没人看（`send` 必发通知）、看了没回执（`pending` + `nudge`）。
- 强制消息五要素：谁→谁 / 要做什么 / 依据（路径+sha1+摘要）/ 时限 / 回执要求；文档只传路径不传正文。
- 新增 `scripts/bus.mjs`（零依赖、只绑 127.0.0.1）与 `references/agent-bus.md`。
- 实测：CLI 全流程、裸 HTTP webhook（UTF-8）、pending/nudge 催办、wait 成功与超时、重复 ack 幂等、404、两窗口端到端。
- 端到端实测后补：`kind` 白名单校验（非法值 400 并列出合法值）、`requires_ack` 未给 `--by` 时自动补 30 分钟时限、
  `verify` 对无引用消息返回 `all_match:null`（区分"无引用"与"校验失败"）、客户端 3 次退避重试。

### V1.2.0（新增自动测试轮次）
- 规则七「自动测试轮次」：用户说「你可以自动化测试几轮」即放行，执行「提交给自己 → 自审 → 自试 → 择优修复」的 N 轮循环；
  默认 3 轮、最多 5 轮，同一 bug 连修 2 轮仍红则停手上报。
- 硬刹车：**用户发来新消息立刻停止轮次**（优先级高于轮数上限与"做到零问题"），当前轮落盘 + ≤8 行汇报。
- 修复择优：每个 bug 至少 2 个修法，按「影响面 / 可验证性 / 回滚成本」打分选一个并记录理由。
- 新增 `references/auto-rounds.md`：轮次文件模板、三类攻击面、择优评分、反模式、插话交互。
- 工作记录新增 `rounds/` 子目录约定；描述加入「自动化测试几轮 / 自己迭代到能用」触发词。
- 经 4 组实测（2 轮正例 / 3 轮跑满 / 用户插话打断 / 普通任务不该触发）后补：记录状态枚举加「暂停」、
  轮次状态加「中断」、明确预算按节点计算的单轮总量口径（≤25 次工具调用）。

### V1.1.0（按"常驻模式"重写）
- 明确生效范围：装上即对所有动手类任务默认生效，不再依赖点名触发。
- 新增规则一「自动落盘」：`.grow-me/<日期>-<slug>.md` 七节记录，先建记录再动手；
  长输出落 `.grow-me/logs/`；交付物先成文件；会话重启/换 agent 只读记录恢复。
- 新增规则二「上下文纪律」：禁整目录通读、禁重复读、禁 echo 大段内容、单次读 ≤200 行。
- 正文瘦身：细节全部外置到 `references/`（`context-and-docs.md`、`porting.md` 新增）。
- 收尾模板增加"记录"一行；自检清单增加记录完整性检查。
- 新增 `references/porting.md`：技能目录 / AGENTS.md 规则 / 一次性 prompt 三种接入方式。
- 经 1 次自测 + 4 次子 agent 冷启动实验（便携性 / 模糊需求 / 上下文恢复 / 无点名常驻）加固：
  追加「可逆假设」第三分类、四档开工优先级、一行紧凑提问式、SKILL.md 内联最小记录骨架、
  `.grow-me/` 落点规则、工作根/产物/下一步可执行化。

### V1.0.0（首个版本）
- Phase 0 追问闸门：一轮问整条前沿（≤5 问），每题带建议与默认值，不回即按默认推进。
- Phase 1 五维工件；Phase 2 预算化循环（≤10 次调用/节点、≤2 次重试）；Phase 3 证据收尾。
- 反偷懒红线 5 条 + 反空转红线 5 条 + 自检清单。
- `scripts/validate-skill.mjs` 自校验脚本；`evals/evals.json` 回归用例。

## 维护建议

- description 决定触发率：把用户真实说过的触发词补进去；改名影响触发，改前先想清楚。
- 红线只增不删；放松时写明理由并记进版本记录。
- 改动后跑 `node scripts/validate-skill.mjs`，必要时用 `evals/evals.json` 回归。
