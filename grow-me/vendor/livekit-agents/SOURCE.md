# 上游来源（LiveKit Agents vendor）

- 仓库：https://github.com/livekit/agents
- 拉取方式：`https://codeload.github.com/livekit/agents/tar.gz/refs/heads/main`
- 拉取时间：2026-11-21
- 上游 HEAD（拉取时 `git ls-remote`）：`d78f39990b2c08a02aa281b3c6a014cd241bbdc8`
- 许可证：Apache License 2.0（见同目录 `LICENSE`、`NOTICE`、`MODEL_LICENSE`）

## 收录内容

| 路径 | 内容 |
|---|---|
| `livekit-agents/` | 上游核心 Python 包源码（`livekit/agents/**`，含 agent_session / agent / voice / llm / stt / tts / vad / metrics / tools 等） |
| `examples/voice_agents/` | 上游语音 Agent 示例（basic_agent、gpt_live、otel_trace、llamaindex-rag、mcp） |
| `UPSTREAM-README.md` | 上游 README（能力清单） |
| `LICENSE` / `NOTICE` / `MODEL_LICENSE` | 上游许可证与声明 |

## 未收录（避免 skill 膨胀，按需去上游取）

- `livekit-plugins/`（各厂商插件包，4.8 MB）
- `tests/`（5.3 MB）
- 其它 `examples/`（3.5 MB）
- `.github/`、`uv.lock`、`pyproject.toml` 等构建文件
- `livekit-agents/livekit/agents/resources/*.ogg` 音频样例：上游用 Git LFS 存储，tarball 里是 0 字节占位，已移除（需要时去上游取真实文件）

## 本地等价运行时

`scripts/voice-agent.mjs` 是本 skill 用零依赖 Node 实现的能力等价版本（不需要 LiveKit 服务器），
能力映射与限制见 `references/livekit-agents.md`。

## 许可合规

再分发时请保留 `LICENSE` / `NOTICE` / `MODEL_LICENSE` 与上述来源说明。
本 skill 自身代码为 MIT；`vendor/livekit-agents/` 内为 Apache-2.0，二者互不影响。
