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

### V1.10.13（语音消息带音频文件，agent 可直接读 WAV）
- 组件条语音发送格式改为 `[voice] <识别文字> | audio: <WAV 路径>`；识别为空时 `[voice] (asr empty) | audio: <路径>`。
- 新增 `scripts/asr-file.ps1`：对任意音频文件跑 SenseVoice→Whisper→SAPI，输出 `ASR_TEXT …`，供 agent 直接“听”文件；
  实测对用户最新录制的 20s 语音输出完整文字。
- 包含 V1.10.12 的播报去重（同一句话 30 分钟内不重播）。

### V1.10.12（播报去重：同一句话不再反复念）
- 用户反馈同一个测试句被反复播报。`voice-notify.ps1` 增加内容哈希去重：同一句话 30 分钟内重复调用直接静默（`spoken:false`），`-ForceAnnounce` 可强制重播。
- 规则十一补硬性要求：**每个任务新写白话摘要文件，禁止复用旧文件**。
- 实测：同一文件连续调用两次 → 第一次 `spoken:true`，第二次 `duplicate suppressed`。

### V1.10.11（播报只念一遍、去掉“已发送”确认音）
- 用户反馈任务播报常念两遍、还会多一句“已发送”。`voice-notify.ps1` 默认 `RepeatBackground=1`（默认只播一遍，需要多遍显式传参）。
- `widget-commands.json` 的 `ackVoice` 改为空字符串，组件条发送后**不再播报“已发送”**，只更新状态文字；想恢复填 `youth` 即可。

### V1.10.10（语音识别换成 SenseVoice，中文不再瞎猜词）
- 用户反馈 Whisper base 把「语音识别」听成「云硬盘/云时边」；实测 SenseVoice 对同一句完全正确。
- 新增 `scripts/asr-sensevoice.py`（sherpa-onnx SenseVoice，int8 CPU，use_itn），模型 228 MB 存于 `~/.grow-me/asr/sensevoice`。
- ASR 顺序改为 **SenseVoice → Whisper → SAPI**；`asr-setup.ps1` 支持 `-Engine sensevoice|whisper`。
- 实测同一段 8.6s 录音：Whisper「现在这个云时边真的没有问题了吗谢谢」→ SenseVoice「现在这个语音识别真的没有问题了吗？」（约 2.0s）。

### V1.10.9（修 Whisper 文字乱码：UTF-8 管道）
- 问题：Python 输出经 PowerShell 管道时按系统代码页解码，Whisper 识别结果变成 `鎴戞鍦ㄧ敤…` 这种乱码，发进聊天也是乱码。
- 修复：widget.ps1 启动时设 `[Console]::OutputEncoding`/`OutputEncoding` 为 UTF-8、`PYTHONIOENCODING=utf-8`；asr-whisper.py 内 `sys.stdout.reconfigure(encoding='utf-8')`。
- 实测：同一段录音输出「我现在正在用这个控制条尝试录音你能不能听到?」（22 字，1.55s）。

### V1.10.8（语音识别换成本地 Whisper，中文准确率大幅提升）
- 默认 ASR 改为 **faster-whisper base**（离线 CPU int8，模型 138 MB 存于 `~/.grow-me/asr/faster-whisper-base`）；SAPI 降级为兜底。
- 新增 `scripts/asr-whisper.py`（soundfile 读 WAV + 重采样 + zh transcribe + VAD）与 `scripts/asr-setup.ps1`（pip 安装 + hf-mirror 下模型）。
- 实测同一段 9.4s 录音：SAPI「我现在正在涌现」→ Whisper「我现在正在用这个控制条尝试录音你能不能听到?」；总耗时约 2.8s。
- 注：模型文件不入技能包，首次用 `asr-setup.ps1` 下载。

### V1.10.7（组件条为什么“没用”：跨桌面目标修复 + 录音自动增益 + ASR 三连）
- 根因：DSH 窗口在另一虚拟桌面（DWM cloaked=2），SetForegroundWindow 失败，点击/粘贴落到 Edge；日志却写 sent。
- 修复：发送前 `IVirtualDesktopManager.FollowCurrent` 把 DSH 拉到当前桌面 → 激活 → 校验前台句柄=目标，否则中止并记 `abort: target not foreground`。
- 录音自动增益：内置麦克风阵列电平极低（满幅 0.1%），录制后自动放大到 ~90% 满幅（≤40 倍）。
- ASR 三连：raw → peak 归一 → 压缩版轮流识别，日志 `asr(...)`；`audio-env.ps1 -Capture` 可查/设麦克风。
- 实测：`target foreground ok` → `sent to [创建 grow me 技能 V1.0.0 — DeepSeek Harness]`；录音 gain=22.1、峰值 90%。

### V1.10.6（组件条单实例：永远只保留最新）
- 启动时按命令行 `-File ...widget.ps1` 精确匹配并结束所有旧实例，再抢命名互斥锁 `Local\GrowMeWidgetSingleton`（处理 AbandonedMutexException）；`instance.json` 记录 pid + buildHash。
- buildHash = `widget.ps1 + widget-native.ps1 + widget-commands.json` 的 SHA256；内容变化后再启动会立刻替换旧版。
- 实测：旧 pid 23700 被新进程结束 → 新 pid 24368 持有锁，实例数=1；重复启动不再叠加。

### V1.10.5（组件条定向发送 + 默认恒为小球）
- 目标窗口选择：前台 DSH 窗口 > 最近一次前台过的 DSH 窗口（看门狗每 1.2s 记录）> 第一个 DSH 窗口；只激活/操作一个窗口，不群发。
- 发送前点击目标窗口底部居中输入区聚焦，再粘贴 + 回车；日志 `sent to [窗口标题]: 内容`。
- 启动强制为小球（不再恢复上次展开状态），避免占地方。
- 实测：`dsh_windows=1`，点击「继续工作」→ `sent to [创建 grow me 技能 V1.0.0 — DeepSeek Harness]`。

### V1.10.4（组件条默认缩成小球，X 收起/展开，桌面上跟随）
- X 改为**收起成球**（不再退出）；默认启动即小球；点小球展开成条；位置与折叠状态存 `~/.grow-me/widget/{pos,state}.json`；右键菜单"退出"关闭。
- 小球与条都可拖拽；窗口限制在工作区不挡任务栏；看门狗 + `IVirtualDesktopManager` 让它在所有桌面可见（切桌面自动跟随）。
- 实测：折叠 44×40、展开 504×34；点球展开 state=false，点 X 收起 state=true。

### V1.10.3（组件条始终最前 + 跟随虚拟桌面）
- 新增 1.2 秒看门狗：每次 `SetWindowPos(HWND_TOPMOST, NOMOVE|NOSIZE|NOACTIVATE)`，被其他置顶窗口压住后自动抬回，且不抢焦点。
- 新增虚拟桌面跟随：`IVirtualDesktopManager`（IsWindowOnCurrentVirtualDesktop / GetWindowDesktopId / MoveWindowToDesktop），切桌面后组件条自动移到当前桌面。
- 日志：`watchdog: topmost=True vd=current`；局限：独占全屏游戏、UAC 安全桌面、管理员权限窗口需以管理员启动。

### V1.10.2（修复组件条点按钮卡死消失）
- 根因：按钮点击处理器里未捕获异常（剪贴板被占用时 `Clipboard.SetText` 抛 `ExternalException`，加上 `$ErrorActionPreference='Stop'` 传播）导致 WPF 宿主进程直接退出。
- 修复：按钮/麦克风处理器全部 try/catch + `Write-WLog` 日志；剪贴板写入重试 3 次；按钮文案改用 `Button.Tag` 传递（去掉 GetNewClosure 作用域隐患）；Send-Harness 全程异常捕获并记录 focus/clipboard 状态。
- 实测：UIAutomation 点击「说中文！」→ 日志 `sent: 说中文！`，组件条存活未崩溃；日志 `~/.grow-me/widget/widget.log`。

### V1.10.1（组件条按钮按用户清单更新）
- 按钮改为用户指定的 5 个：`说中文！` / `有 bug 重新改` / `继续工作` / `停一下:` / `说大白话！`（`widget-commands.json`）。
- 实测重启后组件条显示 5 个按钮 + Mic + X；点击会作为消息发进 DSH 会话（剪贴板+回车）。

### V1.10.0（悬浮组件条：按钮发消息 + 麦克风本地识别）
- 新增 `scripts/widget.ps1`：WPF 悬浮条（Topmost、可拖拽、位置记忆并限制在工作区不挡任务栏）；命令按钮读取 `widget-commands.json`，点击经"激活 DSH 窗口 + 剪贴板粘贴 + 回车"把消息直接发进会话。
- 新增 `scripts/widget-native.ps1`（winmm 录音：16k/16bit/单声道）与 `scripts/widget-asr.ps1`（SAPI 本地离线识别）。
- 麦克风流程：点 Mic 开始/停止 → 存 WAV → 本地 ASR → 发送；识别为空则发送音频路径；发送成功用 youth 短播"已发送"。
- 新增规则十二与 `references/widget.md`；实测录音 2 秒 WAV 63938B、SAPI 识别"你好测试语音识别"成功，组件条已在桌面常驻显示。

### V1.9.7（自身音量拉满：22% 系统音量下也清楚）
- 新增 `scripts/voice-loudness.py`：语音响度最大化（向上压缩 0.92 次幂、tanh 软限幅、峰值归一到 0.98）；`voice-edge-tts.ps1` 合成后**自动**处理（`-NoLoud` 可关）。
- `voice-notify.ps1` 播报前自动**取消静音**（不动系统音量）；`audio-env.ps1` 支持只 `-Unmute`。
- 实测：RMS 0.10→0.24（约 +7.7dB）；系统音量 22% 下用户确认“可以听得很清楚”。

### V1.9.6（排查“听不见”：系统音量仅 22%）
- 新增 `scripts/audio-env.ps1`：用 CoreAudio（IMMDeviceEnumerator/IAudioEndpointVolume）读取默认播放设备名、系统音量与静音状态，并可用 `-SetVolume -Level 0.85 -Unmute` 直接调整（无需外部依赖）。
- 实测：默认设备 `扬声器 (Senary Audio)`、**volume=22%**、mute=False → 调到 **85%** 后 youth 语音可清晰听到。

### V1.9.5（youth 响度修正：音量 +30% + 峰值归一化）
- 用户反馈“声音太小”；`youth` 预设音量改 **+30%**，并对合成波形做**峰值归一化到 -1 dBFS**（`-Normalize` 自动对该预设生效，`-GainDb` 可再叠加增益）。
- 实测同一句：峰值 32% → **90%**，RMS 1358 → **3277**（约 2.4 倍响度）。
- `voice-edge-tts.ps1` 新增 `-GainDb` / `-Normalize` 参数。

### V1.9.4（youth 青年音调音：不尖、音量正常）
- 用户反馈原 youth（+14Hz/-6%/-10%）偏尖（像花栗鼠）、音量偏小；试听 N1–N4 后选定 N1。
- `youth` 预设改为：`Yunxi` + 音调 **+8Hz**、语速 **-2%**、音量 **0%**（`voice-edge-tts.ps1` 与 `voice-notify.ps1` 同步）。

### V1.9.3（新增 youth 青年音预设：16–18 岁温柔开朗男声）
- 用户试听 10 个候选后选定：`Yunxi` 底子 + 音调 +14Hz、语速 -6%、音量 -10%，命名为预设 `youth`。
- `voice-edge-tts.ps1` / `voice-notify.ps1` 均支持 `-Preset youth`；`voice-edge-tts.ps1` 新增 `-Volume` 参数（正负号规范化）。
- 文档：`references/voice-report.md` 预设表加入 youth；默认仍是 `c`（云希）。

### V1.9.2（表情不朗读，按含义/数量改语气）
- `voice-edge-tts.ps1` 新增表情感知：表情不进入朗读文本；按表情类别（开心/难过/生气/惊讶/疑问）与数量（1–3 个，封顶 1.6 倍）调整 `rate`/`pitch`；按表情切句、逐句合成后解码 WAV 拼接播放。
- 新增开关 `-NoEmotion`（关闭情绪）、`-SpeakEmoji`（恢复照读）；负值参数改用 `--rate=`/`--pitch=` 形式避免被当成选项。
- 实测：`Carol，您好😊😊！我是David的AI，六君！🎉` → 两句 cheerful +8%/+5Hz 与 +6%/+4Hz；`😢` → sad -8%/-4Hz；两次都未朗读表情。

### V1.9.1（三档 Edge 音色预设，默认云希）
- `voice-edge-tts.ps1` 新增 `-Preset a|b|c`（A 晓晓女声 / B 晓伊活泼女 / C 云希男声，默认 C）与 `-ListPresets`；`voice-notify.ps1` 同步支持 `-Preset`，默认音色改为 `zh-CN-YunxiNeural`。
- 修复播放链路：Edge MP3 先用 Python `soundfile` 解码为 WAV，再 `SoundPlayer` 播放（此前 MP3 播放器报告成功但变调/无声）。
- 用户试听结论：A/B/C 均可，D 云扬读英文略怪，故选 C 云希为日常播报音色。

### V1.9.0（任务完成语音播报 + Edge 神经语音）
- 新增 `scripts/voice-edge-tts.ps1`：Edge 神经语音（`zh-CN-XiaoxiaoNeural` 等，在线免 Key），WPF 播放 MP3；支持 `-ListVoices/-Rate/-Pitch/-SaveMp3/-NoPlay`。
- 新增 `scripts/voice-notify.ps1`：任务完成播报——读白话摘要文件（或 `-Text`）→ Edge 朗读 → 前台窗口检测（前台不是 DeepSeek Harness/DSH 时加"提醒："并重复 2 遍）；Edge 失败自动回退离线 Piper；JSON 回执 + `~/.grow-me/voice/notify.jsonl` 日志。
- 新增规则十一「任务完成语音播报（白话摘要 + 前台感知）」，红线/自检顺延为十二/十三；新增 `references/voice-report.md`（白话模板与反例、调参）。
- 实测：后台场景 `foreground=false, repeats=2`；前台场景 `foreground=true, repeats=1`，Edge 合成 34–55KB MP3 可回放。

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
