# 实时语音 Agent（对齐 LiveKit Agents）

> 上游：<https://github.com/livekit/agents>（Apache-2.0）。本 skill 做了两件事：
> ① 把上游核心源码与语音示例 vendor 进 `vendor/livekit-agents/`；
> ② 用零依赖 Node 实现了**能力等价**的本地运行时 `scripts/voice-agent.mjs`（不需要 LiveKit 服务器）。

## 上游是什么

LiveKit Agents 是构建**实时可编程语音/多模态 Agent** 的框架：把 STT（语音识别）、LLM、TTS（语音合成）
和实时 API 组合编排，跑在 LiveKit 的 WebRTC 基础设施上，支持打断、轮次检测、工具调用、任务分发、
电话（SIP）接入、客户端 RPC 等。

## 本 skill 的能力映射

| LiveKit Agents 概念 | 本 skill 实现（`scripts/voice-agent.mjs`） |
|---|---|
| `Agent(instructions=...)` | `DEMO_AGENT` / `--agent <json>`，字段 `instructions`、`greeting` |
| `AgentSession` | `class AgentSession`：`start()`、`userTurn()`、`interrupt()`、`end()`、`transcript()` |
| 轮次检测（turn detection） | `turnDetection: "sentence"`：按句切分逐句响应；音频模式带能量 VAD（`rms16`） |
| 打断（barge-in） | `userTurn()` 在说话中触发 `interrupted` 事件并取消当前回复；`interrupt()` 可外部打断 |
| 工具/函数调用 | `agent.tools[]`：`name/description/triggers/schema/handler`，事件 `tool_call`、`tool_result` |
| 插件化 STT / LLM / TTS | `createSTT()` / `createLLM()` / `createTTS()`；离线确定性回退，配 `OPENAI_*` 走 OpenAI 兼容接口 |
| 事件钩子 | `onEvent(ev)`：`session_started` / `user_transcript` / `agent_reply` / `interrupted` / `tool_call` / `session_ended` |
| 转写与指标 | `transcript()` 历史；`metrics`：轮次、打断次数、工具调用数、LLM/TTS 耗时 |
| 服务化 | `serve`：`POST /api/turn`、`GET /api/transcript`、`GET /api/events`(SSE)、`POST /api/interrupt` |

## 快速开始

```powershell
# 1) 命令行对话（内置前台 Agent，离线可用）
node scripts/voice-agent.mjs demo
#   :i 打断   :q 退出

# 2) 自定义 Agent（JSON：instructions / greeting / tools）
node scripts/voice-agent.mjs run --agent .\my-agent.json

# 3) 作为本地服务（8180 端口）
node scripts/voice-agent.mjs serve --port 8180
```

调用示例：

```powershell
curl.exe -s -X POST http://127.0.0.1:8180/api/turn -H "content-type: application/json" -d "{\"text\":\"你们几点营业？\"}"
curl.exe -s http://127.0.0.1:8180/api/transcript
```

接真实模型（OpenAI 兼容）：

```powershell
$env:OPENAI_BASE_URL="https://api.openai.com/v1"
$env:OPENAI_API_KEY="sk-..."
$env:OPENAI_MODEL="gpt-4o-mini"
node scripts/voice-agent.mjs serve --port 8180     # llm 变为 openai-compatible
```

## 离线语音（不接 API、不要 Key）

Windows 自带 SAPI 就能闭环：**麦克风 → 离线识别(zh-CN) → 本地引擎 → 离线合成(zh-CN)**。

```powershell
# 1) 起本地引擎（离线规则 LLM，无需 Key）
node scripts/voice-agent.mjs serve --port 8180
# 2) 说话即对话；说“退出/结束”或 Ctrl+C 停止
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/voice-offline.ps1 -Loop
# 3) 只合成一句到 WAV（验证/留证，不占扬声器）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/voice-offline.ps1 -Text "你好" -SaveWav .\tts.wav
```

- 依赖：Windows 离线语音（SAPI 识别 + Piper 神经合成，模型缓存在 `%USERPROFILE%\.grow-me\tts\piper`，不联网运行）。
- **中英混读**：`voice-hybrid-tts.ps1` 按字符自动分流——中文用 `zh_CN-huayan-medium`，英文用 `en_US-lessac-medium`，再拼成同一段 22050Hz WAV；所以 "AI Agent" 会被英文音色正确读出。
- 换声音/语速：`voice-offline.ps1 -Loop -LengthScale 1.1`（放慢）；`-TtsEngine piper`（纯中文 huayan）、`winrt`（微软 Yaoyao/Kangkang）、`sapi`（旧 Huihui）。
- 首次下载模型：`powershell -File scripts/voice-hybrid-tts.ps1 -Text "你好" -Ensure`（hf-mirror，两个模型约 63MB/个）。
- 局限：Windows 离线识别引擎不是大模型，嘈杂环境准确率一般；要云端级效果再接真实 STT（见上文插件）。

## 想用上游完整能力（生产级 WebRTC / 电话）

```bash
pip install "livekit-agents[openai,silero,deepgram,cartesia]"
# 还需要一个 LiveKit 服务器（Cloud 或自建）与各厂商 API Key
python vendor/livekit-agents/examples/voice_agents/basic_agent.py dev
```

上游示例已经在 `vendor/livekit-agents/examples/voice_agents/`（basic_agent、gpt_live、otel_trace、
llamaindex-rag、mcp），可直接对照改造。

## 明确不做的（诚实边界）

- **WebRTC/SIP/电话**：本实现不建媒体通道、不做音频编解码与抖动缓冲 —— 需要时用上游 + LiveKit 服务器。
- **真实 STT/TTS**：离线模式是确定性回退（文本直通/文本返回）；真实语音可用 Windows SAPI 离线语音（`scripts/voice-offline.ps1`），要云端级效果再接插件（OpenAI Realtime 等）。
- **多 Agent 任务分发/调度**：上游的 job dispatch、worker 池未复刻。
- **语义轮次模型**：上游用 transformer 判停；本实现按句切分 + 能量 VAD。

## 许可

- `vendor/livekit-agents/`：Apache-2.0，保留 `LICENSE`、`NOTICE`、`MODEL_LICENSE`、`SOURCE.md`。
- `scripts/voice-agent.mjs`、`references/livekit-agents.md`：MIT（本 skill 自身）。
