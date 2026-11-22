# Changelog

本项目遵循「版本号写进 `VERSION`、`SKILL.md` metadata、`evals.json` 三处必须一致」的约定。
发布流程见 [RELEASE.md](RELEASE.md)。

## V1.10.2 — 修复组件条点按钮卡死消失

- 根因：按钮处理器未捕获异常（剪贴板占用时 Clipboard.SetText 抛 ExternalException + EAP Stop）导致 WPF 宿主退出。
- 修复：按钮/麦克风处理器 try/catch + 日志；剪贴板重试 3 次；按钮文案走 Tag；Send-Harness 全程捕获并记录 focus/clipboard。
- 实测：UIAutomation 点击「说中文！」→ 日志 `sent: 说中文！`，组件条存活；日志在 `~/.grow-me/widget/widget.log`。

## V1.10.1 — 组件条按钮按用户清单更新

- 按钮改为：`说中文！` / `有 bug 重新改` / `继续工作` / `停一下:` / `说大白话！`。
- 重启验证：5 按钮 + Mic + X 正常显示；点击发消息进 DSH 会话。

## V1.10.0 — 悬浮组件条（按钮发消息 + 麦克风本地识别）

- 新增 `scripts/widget.ps1`：WPF 悬浮条，Topmost、可拖拽、位置记忆并限制在工作区不挡任务栏；按钮读取 `widget-commands.json`，点击经"激活 DSH 窗口 + 剪贴板粘贴 + 回车"把消息直接发进会话。
- 新增 `scripts/widget-native.ps1`（winmm 录音 16k/16bit/单声道）与 `scripts/widget-asr.ps1`（Windows SAPI 本地离线识别）。
- 麦克风流程：点 Mic 开始/停止 → WAV → 本地 ASR → 发送；识别为空则发送音频路径；发送成功用 youth 短播"已发送"。
- 新增规则十二与 `references/widget.md`；实测录音 2 秒 WAV 63938B、SAPI 识别成功，组件条已常驻显示。

## V1.9.7 — 自身音量拉满（22% 系统音量下也清楚）

- 新增 `scripts/voice-loudness.py`：语音响度最大化（向上压缩 + tanh 软限幅 + 峰值归一 0.98）；Edge 合成后自动处理（`-NoLoud` 可关）。
- `voice-notify.ps1` 播报前自动取消静音（不改用户音量）；`audio-env.ps1` 支持只 `-Unmute`。
- 实测 RMS 0.10→0.24（约 +7.7dB），系统音量 22% 下用户确认清晰。

## V1.9.6 — 排查“听不见”：系统音量仅 22%

- 新增 `scripts/audio-env.ps1`（CoreAudio）：读默认播放设备/系统音量/静音，可 `-SetVolume -Level 0.85 -Unmute` 直接调整。
- 实测默认设备 `扬声器 (Senary Audio)`、volume 22% → 调到 85% 后 youth 语音清晰可听。

## V1.9.5 — youth 响度修正（音量 +30% + 峰值归一化）

- 用户反馈声音太小；`youth` 预设音量改 +30%，并对合成波形做峰值归一化到 -1 dBFS（`-Normalize` 自动生效）。
- `voice-edge-tts.ps1` 新增 `-GainDb` / `-Normalize`。
- 实测：峰值 32% → 90%，RMS 1358 → 3277（约 2.4 倍）。

## V1.9.4 — youth 青年音调音（不尖、音量正常）

- 用户反馈原 youth（+14Hz、-6%、-10% 音量）偏尖像花栗鼠、音量偏小；试听 N1–N4 后选定 N1。
- `youth` 预设改为：`Yunxi` + 音调 **+8Hz**、语速 **-2%**、音量 **0%**。

## V1.9.3 — 新增 youth 青年音预设（16–18 岁温柔开朗男声）

- 预设 `youth`：`Yunxi` + 音调 +14Hz、语速 -6%、音量 -10%；`voice-edge-tts.ps1` 与 `voice-notify.ps1` 均支持 `-Preset youth`。
- `voice-edge-tts.ps1` 新增 `-Volume` 参数（正负号规范化）；默认仍是 `c`（云希）。

## V1.9.2 — 表情不朗读，按含义/数量改语气

- `voice-edge-tts.ps1` 表情感知：表情不进入朗读文本；按类别（开心/难过/生气/惊讶/疑问）与数量（1–3 个，封顶 1.6 倍）调 `rate`/`pitch`；按表情切句、逐句合成后解码 WAV 拼接播放。
- 新增 `-NoEmotion`（关闭）、`-SpeakEmoji`（照读）；负值参数改用 `--rate=`/`--pitch=` 形式。
- 实测：`Carol，您好😊😊！我是David的AI，六君！🎉` → cheerful +8%/+5Hz、+6%/+4Hz；`😢` → sad -8%/-4Hz；表情均未朗读。

## V1.9.1 — 三档 Edge 音色预设，默认云希（C）

- `voice-edge-tts.ps1` 新增 `-Preset a|b|c` 与 `-ListPresets`（A 晓晓女声 / B 晓伊活泼女 / C 云希男声，**默认 C**）。
- `voice-notify.ps1` 同步支持 `-Preset`，默认音色改为 `zh-CN-YunxiNeural`。
- 修复播放链路：Edge MP3 先经 Python `soundfile` 解码成 WAV，再 `SoundPlayer` 播放（此前 MP3 播放器报告成功但变调/无声）。
- 用户试听结论：A/B/C 均可、D 云扬读英文略怪 → 日常用 C 云希。

## V1.9.0 — 任务完成语音播报（白话摘要 + 前台感知 + Edge 神经语音）

- 新增 `scripts/voice-edge-tts.ps1`：Edge 神经语音（zh-CN-XiaoxiaoNeural 等，在线免 Key），WPF 播放 MP3。
- 新增 `scripts/voice-notify.ps1`：读白话摘要文件 → Edge 朗读 → 前台检测（不在 DeepSeek Harness/DSH 窗口时加“提醒：”并重复 2 遍）→ Edge 失败回退离线 Piper；JSON 回执 + `~/.grow-me/voice/notify.jsonl`。
- 新增规则十一「任务完成语音播报」，红线/自检顺延为十二/十三；新增 `references/voice-report.md`。
- 实测：后台 `foreground=false, repeats=2`；前台 `foreground=true, repeats=1`。

## V1.8.3 — 离线神经语音 + 中英混读修音

- 新增 `scripts/voice-piper-tts.ps1`（Piper 离线神经 TTS，`-Ensure` 经 hf-mirror 下模型）与 `scripts/voice-hybrid-tts.ps1`（中文 huayan + 英文 lessac 自动分流、重采样拼接）。
- `voice-offline.ps1` 默认引擎改为 `hybrid`（回退 piper→winrt→sapi）；修掉 “AI Agent 读成 爱爱进”。
- 模型缓存在 `%USERPROFILE%\.grow-me\tts\piper`（约 63MB×2，不进技能包）；安装 `py -3 -m pip install piper-tts`。
- 实测：同一句 118KB / 2.9s。

## V1.8.2 — 换更好听的离线声音（WinRT 自然语音）

- 新增 `scripts/voice-winrt-tts.ps1`：WinRT `Windows.Media.SpeechSynthesis` 调 Windows 自然语音（`-ListVoices`/`-Voice`/`-SaveWav`/`-Rate`）。
- `voice-offline.ps1` 支持 `-Voice`（Yaoyao/Kangkang 等）与 `-TtsEngine`。

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
