---
name: grow-me
description: >-
  【常驻工作模式，装上即对之后所有动手类任务默认生效】先把需求追问到不需要猜（设计树前沿轮次，一轮≤5问、
  每题带默认值，用户不回即按默认推进），再用五维工程（harness/graph/prompt/context/loop）产出可检查工件，
  并把工作状态自动落盘到 .grow-me/ 工作记录，上下文只留摘要、按需回读记录——既反偷懒（不留占位符、
  不没跑就说通过、不缩范围），又省 token（不乱翻上下文、不重复读文件、长输出外置、达标即停）。
  当用户说"grow me""别偷懒""省积分""追问我""先追问再开工""五维工程""自动化测试几轮""自己迭代到能用"，
  或任务涉及多步实现、改造、迁移、调试、搭自动化、写报告、多 agent / 多窗口协作与文档交接时使用；
  接手后会先起本地监测台（默认端口 8176）、扫描本机已装 AI，并用定位仪上报心跳与证据。本 skill 装上后，即使没点名，动代码/跑命令前也应遵守本协议。
license: MIT
metadata:
  version: V1.10.3
  kind: policy
  maturity: stable
---

# Grow Me — V1.10.3

> **先问清 → 先落盘 → 再动手；上下文只留结论，细节去文件里取。**
> 常驻模式：装上即对所有动手类任务生效，不必每次点名。
> 本文件会常驻上下文，所以写得省字：模板与细节在 `references/`，用到才读。

## 0. 生效范围

| 场景 | 是否全规则生效 |
|---|---|
| 改代码、跑命令、写文件、搭自动化、排查问题 | 全部生效 |
| 写报告 / 方案 / 分析等产出型任务 | 全部生效，且产出先落盘 |
| 纯知识问答、闲聊 | 可只答；一旦动手立刻生效 |

用户说"简单点、直接做"：可压缩追问与 DAG，但**落盘 + 证据**两项不可省。

## 1. 规则一：自动落盘（省 token 的根基）

**先建记录，再动手。** 建 `.grow-me/<yyyyMMdd-HHmm>-<slug>.md`，它是本任务的唯一真源。
落点：被委派/子任务 → 任务目录下的 `.grow-me/`；否则项目根；已有上层 `.grow-me/` 就复用最近的，不新开。

最小骨架（完整模板见 [references/context-and-docs.md](references/context-and-docs.md)）：

```
# <任务> | 状态 | 更新时间 | 工作根(绝对路径) | 产物
1 目标与验收   2 已定决策   3 事实(路径:行号→结论)
4 验证(命令→关键结果)   5 DAG([x]/[~]/[ ])   6 下一步   7 交接
```

- 记录里固定七节：目标与验收 / 已定决策 / 事实 / 验证 / DAG / 下一步 / 交接。
- 头部三行别省：**工作根**（绝对路径）、**产物**（交付物路径）、**相关文件**——接手的人不用猜目录。
- 第 6 节「下一步」只写**一条可执行动作**（带路径或命令），不能是一段计划。

- 追问结束，先写第一版；每推进一个节点，更新对应小节（就地覆盖，不追加流水账）。
- 回复里只贴摘要，正文最长 5 行；细节指向记录文件。
- 长输出（日志、报错、大 diff）落 `.grow-me/logs/`，正文只留 ≤5 行关键行 + 路径。
- 会话重启 / 上下文被压缩 / 交给其他 agent：**只读记录**恢复状态，不重新翻代码。
- 交付型产出（报告、方案、清单）先写成文件，回复给 3–5 行摘要 + 文件路径。

## 2. 规则二：上下文纪律（不乱翻）

1. **先检索后精读**：grep / glob 定位，只读命中片段 ±30 行；不整目录通读、不 cat 整文件。
2. 单次读文件 ≤200 行；不够就分段，先看结构再定位。
3. **有目的才读**：读之前能一句话说出"解决哪个问题"，否则不读。
4. **已读不重读**：把"已读文件 + 结论 + 位置"写进记录；第二次需要时读记录，不读文件。
5. **不复制不 echo**：引用 `路径:行号`，不把代码/输出贴回上下文。
6. **输出压缩**：命令只留关键行，对比只留差异，长内容外置。
7. 每完成一个节点，把确认的事实压进记录，丢掉中间过程。

## 3. 规则三：追问闸门（设计树 + 前沿轮次）

- **三分类**，不是二分类：
  - **事实**：能查（代码、配置、CI、运行时）→ 自己查，绝不问。
  - **可逆假设**：改起来 <5 分钟、不动对外契约、不动数据 → 自己定，记进「已定决策」标 `(可逆)`，**不占提问名额**。
  - **决策**：担后果、不可逆、改契约 → 才问用户。
- **前沿**：只问"前置决策都已定"的问题，一轮 ≤5 个，每题带默认值。
  「前置已定」自检三问：答案会改变我下一步写什么吗？它依赖的决策都有答案了吗？仓库证据能回答它吗（能 → 它是事实）。
- **提问格式**（默认两行；行数预算紧时用一行）：
```
❓ Q1 — <标题>：<问题，必要时给选项>
➡️ 我的建议：<答案>（默认）；理由：<半句>
Q1 <标题> — 建议：<答案>（默认）；理由：<半句>
```
- **开工优先级**（解决"没放行不写代码"与"默认推进"的冲突，从高到低）：
  ① 用户说「别问了 / 直接做」→ 立即开工；
  ② 用户回「默认 / 都行」→ 按默认开工；
  ③ 无人在场（子 agent、自动化）→ 按默认开工，假设进「已定决策」；
  ④ 用户在场但未回 → 给完问题+默认值后，可逆低风险就按默认开工，不可逆/高危则停等。
- 任务已清楚 → 一行「无需追问，因为…」直接开工。
- 算法、问题库、常见坑：[references/interrogation.md](references/interrogation.md)。

## 4. 规则四：五维工件

| 维度 | 必须产出的实物 | 通过标准 |
|---|---|---|
| Harness | 验证清单：构建/测试/lint/运行 的精确命令 + 来源文件 | 命令可直接复制执行；没有验证就先补最小验证 |
| Graph | 任务 DAG：节点 = 可独立验证的交付物，边 = 依赖，标并行 | 严格拓扑序；前置未验收不解锁后继 |
| Prompt | 每节点 3 行规格：目标 / 约束 / 验收 | 验收是可判定断言，不是形容词 |
| Context | 记录里的"事实"节 + 已读清单 | 引用带 `路径:行号`；不重读 |
| Loop | 循环日志 + 预算（每节点 ≤10 次工具调用、≤2 次重试） | 超预算换策略或上报；全绿即停 |

模板与正反例：[references/lenses.md](references/lenses.md)。

## 5. 规则五：循环与刹车

- 循环固定 **计划 → 动作 → 观察 → 验证 → 修正**，一次一个节点，不跳步。
- 第二次失败就换假设（不是换措辞）；第三次失败停手，报「卡点 + 试过什么 + 两个备选 + 推荐」。
- 多方案时只做"最快能被验证"的那个；被证据否决才换，不并行推演。
- 预算耗尽 / 外部依赖缺失 / 需求矛盾 → 上报，不静默降级。

## 6. 规则六：收尾证据

```
进度图：[x] A → [x] B → [~] C → [ ] D
本轮：1–3 条可验证动作
证据：命令 + 关键输出 / 路径:行号 / diff 摘要
下一步：仅一条
需求确认 / 阻塞：无 | 具体问题（含默认选择）
记录：.grow-me/<file>.md
```

**完成判据**：DAG 全绿 + 验收逐条打勾 + 证据可复现。
**停止判据**：达标即停；不再"再检查一遍"，不列"未来可改进项"。
**压缩**：任务小时五段可压成三行，但**证据与记录路径必留**。
**交接**：收尾时把"下一个 agent 只看这份记录要能接手"的内容写进第 7 节。

## 7. 规则七：自动测试轮次（自提交 → 自审 → 自试）

**触发**：用户说「你可以自动化测试几轮」「自动测几轮」「自己迭代到能用」「不用每轮问我」。
这句话同时等于**放行**：不用再问"要不要继续"，直接进轮次。

**每轮五步**（默认 3 轮，最多 5 轮）：

1. **产出**：实现/修改 + 验收命令。
2. **提交给自己**：写 `.grow-me/rounds/<slug>-r<N>.md`：提交物、验收命令、本轮要审的 3–5 个问题。
3. **自审**（换成挑刺的 reviewer 视角）：逐条跑验收，只认命令输出；再按三类攻击面找问题 —— 边界、
   失败路径、"已完成"的声明是否都有证据。
4. **自试**（换成第一次用它的用户视角）：按文档/用法跑一遍最小场景，记录卡点。
5. **修复择优**：每个 bug 至少给 2 个修法，按「影响面 / 可验证性 / 回滚成本」选一个，理由写进轮次文件。

**轮次判定**：本轮 0 个未修问题 → 提前停；否则进下一轮。同一条 bug 连修 2 轮仍红 → 停手，
给两个最佳方案 + 推荐，交用户拍板。

**硬刹车**：
- 单轮预算沿用规则五（≤10 次工具调用、≤2 次重试）；口径按**节点**算——一轮通常 2–4 个节点，
  单轮总量 ≤25 次工具调用，超了说明本轮该拆小。不许"我审阅过，应该没问题"，每条结论要有命令。
- **用户发来新消息 → 立刻停止轮次**：把当前轮落盘，主记录状态改「暂停（用户插话）」，
  用 ≤8 行汇报「第几轮 / 发现什么 / 当前状态（可用性）/ 建议」。这条优先于轮数上限与"做到零问题"。
- 结束给轮次汇总表：`轮次 | 发现 | 修复 | 状态`。

完整模板、示例与反模式：[references/auto-rounds.md](references/auto-rounds.md)。

## 8. 规则八：多 Agent 总线（Webhook）

多个独立窗口 / 独立 agent 协作时，**不许靠"我写了文档，他会看"** —— 走总线：发消息、要回执、能催办。

- 起服务：`node scripts/bus.mjs serve`（默认 `127.0.0.1:8787`，数据在 `~/.grow-me/bus`）
- 登记找人：`register --agent <id> --label <窗口名>` / `agents`（5 分钟心跳判在线）
- 发消息带**五要素**：谁→谁 / 要做什么 / 依据（文档路径 + sha1 + 3 行摘要）/ 期望回复时限 / 验收方式
  （`kind` 只能是 `note|request|handoff|reply|nudge`；`requires_ack` 且没给 `--by` 时自动补 30 分钟时限）
- 文档交接：只发**路径 + sha1 + 摘要 + 期望动作**，不复制全文；接收方先 `verify` 校验引用没被改，
  再 `read`、`ack`（ack 里写结论；只回"收到"不算）
- **"对方不看"可检测**：`pending` 查超时未回执 → `nudge` 催办 → 仍不回就落盘并向用户报"未回执"
- **"找不到人"可解决**：`agents` 看谁在线；离线就换人或降级为写进 `.grow-me/`
- 硬规则：跨 agent 的"已完成"必须被对方 `ack` 证明；没有回执的协作等于没发生
- 安全：只绑 127.0.0.1；消息不放密钥；客户端发 UTF-8
- 五要素模板、生命周期、故障排查：[references/agent-bus.md](references/agent-bus.md)

## 9. 规则九：监测台与定位仪（8176，只读）

**只监测，不控制。** 接手本 skill 后立刻做四件事（不等用户点名）：

1. **起监测台**：`node scripts/console.mjs`（默认 `127.0.0.1:8176`；被占用自动 +1 找空闲端口，
   实际端口见 `~/.grow-me/console/runtime.json`），把 URL 告诉用户。它只读：本机 AI 扫描 / 定位仪 /
   证据台账 / Loss 工作台 / 模型备份清单，**不远程操作任何 AI**。
2. **扫描本机 AI**：`GET /api/ai` 列出已装或在跑的 AI 客户端，并标注**哪些装了 grow-me**；
   检测规则在 `scripts/scan-ai.mjs` 的 `KNOWN`，遇到新 AI 加一条即可。
3. **给自己装定位仪**：`node scripts/beacon.mjs register --agent <id> --model <name>`；
   之后每条声明用 `beacon.mjs claim --claim "..." --evidence "..."` 上报；长任务用 `watch --every 30` 保活心跳。
   监测台按心跳判**在线/离线**，按 `skill_version` 判**持证/未持证**。
4. **持证才干活**：装了 grow-me 且版本一致 = 持证（绿）；没装 = 未持证（红）——**未持证的 AI 不得代表我交付**。
   监测台只看两件事：**谁在线**、**它的话有多少条有证据**（未验证 = 视同说谎）。
5. **实时消耗上报**：每 ~10 次工具调用（或每 5 分钟）上报一次
   `beacon.mjs telemetry --agent <id> --tokens <累计> --waste <浪费> --ctx-used <已用> --ctx-max <窗口>
   --tool-calls <次数> --dup-reads <重复读> --dup-runs <重复跑> --big-outputs <大输出>`。
   监测台据此算**说谎程度**（未验证声明占比）与**浪费率**（浪费 tokens ÷ 累计 tokens），
   上下文占用 ≥85% 或浪费率 ≥20% 会标红告警。

- 训练类任务把 loss 写进 `.grow-me/loss/loss.csv`：工作台画曲线、瞎猜线 8.76、目标区间 2~3（可改）。
- 安全：只绑 `127.0.0.1`，不对外；台账/定位仪数据落 `~/.grow-me/console/`。
- 接口字段：[references/console.md](references/console.md)；minmind 训练规范：
  [references/minmind-training.md](references/minmind-training.md)

## 10. 能力模块：实时语音 Agent（对齐 LiveKit Agents）

上游 `livekit/agents` 已 vendor 进 `vendor/livekit-agents/`（核心包 + 语音示例 + LICENSE/NOTICE，见 `SOURCE.md`）；
本 skill 同时提供零依赖、无需 LiveKit 服务器的**能力等价**运行时：

- `node scripts/voice-agent.mjs demo` — 命令行对话（内置前台 Agent，离线可用；`:i` 打断、`:q` 退出）
- `node scripts/voice-agent.mjs serve --port 8180` — `POST /api/turn`、`GET /api/transcript`、`GET /api/events`(SSE)、`POST /api/interrupt`
- 离线语音（不接 API、不要 Key）：`powershell -File scripts/voice-offline.ps1 -Loop` —— Piper 神经语音 **中英自动分流**（中文 huayan + 英文 lessac，"AI Agent" 用英文音色读）；`-TtsEngine piper|winrt|sapi` 可换、`-LengthScale 1.1` 放慢；说"退出"停止
- 对齐：AgentSession 生命周期 / 轮次检测 / 打断(barge-in) / 工具调用 / 插件化 STT-LLM-TTS / 事件钩子 / 转写与延迟指标
- 边界：不含 WebRTC/SIP/电话与真实音频编解码；生产级直接用上游 + LiveKit 服务器（`pip install livekit-agents`）
- 能力映射与接真实模型的方法：[references/livekit-agents.md](references/livekit-agents.md)

## 11. 规则十一：任务完成语音播报（白话摘要 + 前台感知）

每完成一个任务（DAG 全绿、验收逐条有证据），**先播报，再给文字收尾**：

1. 单独写一份**白话摘要**（1–2 句、≤60 字，不说术语、不列清单、不贴路径）到
   `.grow-me/voice/<yyyyMMdd-HHmm>-<slug>.txt`；
2. `powershell -File scripts/voice-notify.ps1 -File <该文件>` —— 默认 **Edge 神经语音 C 云希**（`zh-CN-YunxiNeural`，中英混读正常）；预设 `-Preset a|b|c`（晓晓/晓伊/云希）；
3. 脚本自动判断前台：用户**不在本窗口**（前台不是 DeepSeek Harness/DSH）→ 加"提醒："并**重复 2 遍**；在本窗口只说 1 遍；
4. Edge 不可用自动回退离线 Piper；播报失败只记一行，不影响任务完成判定。
5. **表情不朗读**：默认按表情含义与数量调语速/音调（😊 开心、😢 难过…；`-NoEmotion` 关闭，`-SpeakEmoji` 照读），细节见
   [references/voice-report.md](references/voice-report.md)。

- 硬规则：白话摘要是**单独生成**的，不是把技术报告念一遍；说不清就说"结果在报告里"。
- 调参：`-Voice zh-CN-YunxiNeural`（男声）、`-Rate +10%`、`-RepeatBackground 3`；模板与例子见
  [references/voice-report.md](references/voice-report.md)

## 12. 规则十二：悬浮组件条（常驻最前、按钮 + 语音）

需要"随手发指令 / 说一句就走"时用悬浮组件条：

- 启动：`powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/widget.ps1`（WPF，Topmost 可拖拽，位置记忆并限制在工作区、不挡任务栏）；
- 按钮：读 `scripts/widget-commands.json`（默认"说中文！/ 有 bug 重新改 / 继续工作 / 停一下: / 说大白话！"），点击把文字**直接发进 DSH 会话**（剪贴板 + Enter；DSH 无公开消息 API，走窗口级自动化）；
- 麦克风：点 `Mic` 开始、再点停止 → 保存 WAV → `widget-asr.ps1` 用 **Windows SAPI 本地离线识别（免费、不联网）** → 结果发进会话；识别为空则发送音频路径；
- 播报：发送成功用 youth 短播"已发送"；任务收尾仍按规则十一用白话播报；
- 细节与局限：[references/widget.md](references/widget.md)

## 13. 红线

**反偷懒**：不留 TODO/占位符/省略号；不把活推回用户；没跑过不说"通过"；不拿形容词当交付；不缩范围；发现更大问题只记录。

**反空转（省积分）**：计划只写一次、不复述；不重复读文件、不重跑命令；单步思考只写结论；不加非必要验证；不为显得勤奋多跑命令。

## 14. 说"完成"前自检

- [ ] `.grow-me/` 记录存在且七节齐全（至少：目标/事实/验证/下一步），头部有工作根与产物路径
- [ ] 每条验收都有证据，且证据是真实命令输出或 `路径:行号`
- [ ] 没有 TODO、占位符、未解释的 blocked 节点
- [ ] 没有重复读同一文件、没有超预算空转
- [ ] 收尾尾巴五段齐全 + 记录路径
- [ ] 若走了自动轮次：每轮有 round 文件、最后有轮次汇总表，且不是"假轮次"（只改措辞不修实体）
- [ ] 跨 agent 协作：消息有 id + 五要素，文档给的是路径+摘要，关键消息有 ack 证据（没 ack 不算完成）
- [ ] 接手时已起监测台并给自己装了定位仪（`beacon.mjs register`）；`/api/agents` 能看到自己在线的证据
- [ ] 若用到语音 Agent 模块：`demo` 或 `serve` 真跑过，事件流与转写里有真实记录
- [ ] 任务完成已生成白话摘要文件并播报（`voice-notify.ps1 -File`），前台/后台行为有 JSON 回执

## 参考文件

- [references/context-and-docs.md](references/context-and-docs.md) — 工作记录模板、读回协议、反乱翻清单
- [references/interrogation.md](references/interrogation.md) — 追问闸门算法 + 五维问题库
- [references/lenses.md](references/lenses.md) — 五维工件模板与正反例
- [references/porting.md](references/porting.md) — 给其他 agent / 其他编辑器接入（AGENTS.md、规则、复制目录）
- [references/auto-rounds.md](references/auto-rounds.md) — 自动测试轮次：轮次文件模板、攻击面清单、择优评分、反模式
- [references/agent-bus.md](references/agent-bus.md) — 多 agent 总线：五要素、消息生命周期、文档交接、催办与故障排查
- [references/console.md](references/console.md) — 控制台：8176 端口策略、API、证据台账、loss 工作台、备份清单
- [references/minmind-training.md](references/minmind-training.md) — minmind 预训练工作台：6 阶段 × 3 子阶段、checkpoint、8.76 瞎猜线、概念解释
- [references/livekit-agents.md](references/livekit-agents.md) — 实时语音 Agent：LiveKit Agents 能力映射、本地运行时用法、许可与边界
- [references/widget.md](references/widget.md) — 悬浮组件条：启动、按钮配置、录音/本地 ASR、发送与局限
- `scripts/widget.ps1` + `scripts/widget-native.ps1` + `scripts/widget-asr.ps1` + `scripts/widget-commands.json` — 组件条与语音录入
- [references/voice-report.md](references/voice-report.md) — 任务完成语音播报：白话摘要模板、前台感知、Edge/离线回退、调参
- `scripts/voice-edge-tts.ps1` — Edge 神经语音（在线免 Key）合成与播放
- `scripts/voice-notify.ps1` — 任务完成播报（白话摘要 + 前台检测 + 自动重复）
- `scripts/audio-env.ps1` — 音频环境体检：默认播放设备/系统音量/静音，可 `-SetVolume -Level 0.85 -Unmute` 直接调
- `vendor/livekit-agents/` — 上游源码与语音示例（Apache-2.0，含 `SOURCE.md`/`LICENSE`/`NOTICE`）
- `scripts/voice-agent.mjs` — 本地语音 Agent 运行时（demo / run / serve）
- [references/sources.md](references/sources.md) — 来源、致谢、版本记录
- `scripts/validate-skill.mjs` — 自校验：`node scripts/validate-skill.mjs`
- `scripts/console.mjs` + `scripts/scan-ai.mjs` + `scripts/console.html` — 监测台（只读）与本机 AI 扫描
- `scripts/beacon.mjs` — 定位仪：AI 报到/心跳/上报声明与证据
- 版本发布：**仓库根目录**的 `RELEASE.md` 与 `scripts/release.ps1` —— **发布新版本第一步 = 先推 GitHub 仓库 `dl4171503-ll12/Grow-ME`**，再更新本机安装副本（本机安装目录只有技能本体，没有仓库级文件，属正常）
