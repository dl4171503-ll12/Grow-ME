# 任务完成语音播报（规则十一）

> 目的：任务做完时，用户可能没看窗口。用一句**白话**把结果说出来；如果用户不在本窗口，就多喊两遍。

## 什么时候播

- 每个任务到达「完成判据」时（DAG 全绿 + 验收逐条有证据）→ 必须先播，再给文字收尾。
- 任务被打断/暂停/失败不上报完成 → 不播（避免误报）。

## 白话摘要怎么写（关键）

单独写成 `.grow-me/voice/<yyyyMMdd-HHmm>-<slug>.txt`，然后 `voice-notify.ps1 -File <该文件>`。

- **每个任务必须新写一份**，禁止复用上一个任务的旧文件（否则会把旧句子反复念，用户会烦）；
- 同一句话 **30 分钟内不会重复播**：`voice-notify.ps1` 用内容哈希去重，重复调用直接静默返回 `spoken:false`；确需重播用 `-ForceAnnounce`。

| 要求 | 说明 |
|---|---|
| 1–2 句，≤60 字 | 长了没人听完 |
| 不说术语 | 不出现 "DAG/证据/API/P95" 这类词 |
| 不列清单、不贴路径 | 路径放文字回复里 |
| 结论先行 | 先说"做完了/没做成"，再说一句关键结果 |
| 像跟人说话 | "报告放桌面了，你看看行不行" |

好例子：

- `换好 Edge 语音了，以后任务做完会自动白话播报。`
- `报告写好了，放在桌面那个新文件里，你看一眼就行。`
- `这次没做成，卡在登录，我已经把原因写进记录了。`

反例（禁止）：

- `DAG 节点 A/B/C 全绿，验收命令 npm test 通过，产物路径 D:\...`（技术腔 + 念清单）
- `任务已完成。`（太干，没有信息）

## 前台感知（自动）

`voice-notify.ps1` 会取当前前台窗口的进程名与标题，与本窗口匹配（默认 `DeepSeek Harness|DeepSeek|Harness|DSH|127.0.0.1:52352`）：

- 播报**默认只播 1 遍**（无论前后台）；`-RepeatBackground N` 可显式要求多遍（默认 1）。
- 不在前台时会在前面加"提醒："，但**不再重复**——说一遍用户就能听到。
- 判断结果会打印成一行 JSON，并写入 `%USERPROFILE%\.grow-me\voice\notify.jsonl`，可复查。

## 命令

```powershell
# 用文件（推荐，任务完成时）
powershell -File scripts/voice-notify.ps1 -File .grow-me/voice/20261121-1955-edge-voice.txt

# 直接用文字
powershell -File scripts/voice-notify.ps1 -Text "做完了，报告已经生成。"

# 换声音/语速/重复次数
powershell -File scripts/voice-notify.ps1 -File x.txt -Voice zh-CN-YunxiNeural -Rate +10% -RepeatBackground 3
```

## 表情符号处理（默认不读，改成语气）

`voice-edge-tts.ps1` 默认开启表情感知（`-NoEmotion` 可关，`-SpeakEmoji` 可恢复照读）：

1. 表情符号**不进入朗读文本**（不会被念成"笑脸"或乱码）；
2. 按表情的**含义**给所在句子换情绪，按**数量**放大（1 个≈1.0 倍，2 个≈1.3 倍，3 个封顶 1.6 倍）；
3. 实现方式：按表情切句 → 每句单独用 Edge 合成（不同 `rate`/`pitch`）→ 解码 WAV → 拼接播放。

| 表情类 | 例子 | 效果 |
|---|---|---|
| 开心 | 🙂😊😄😁😍❤️✨👍🎉 | 语速 +6%、音调 +4Hz（越多越明显） |
| 难过 | 😢😭😞😔🥺 | 语速 -8%、音调 -4Hz |
| 生气 | 😡😠🤬💢 | 语速 +10%、音调 -6Hz |
| 惊讶 | 😮😲😱🤯 | 语速 +8%、音调 +8Hz |
| 疑问 | ❓❔❕❗ | 语速 +2%、音调 +5Hz |

示例：

```powershell
# 原句（无表情）
... voice-edge-tts.ps1 -Text "Carol，您好，我是David的AI，六君！"
# 带表情：😊😊 归前一句加强，🎉 收尾欢快，都不读出来
... voice-edge-tts.ps1 -Text "Carol，您好😊😊！我是David的AI，六君！🎉"
# 悲伤对照
... voice-edge-tts.ps1 -Text "Carol，您好😢。我是David的AI，六君。"
```

## 响度（自身音量拉满）

- 所有 Edge 合成音频在播放前自动做**响度最大化**：`scripts/voice-loudness.py`（向上压缩 + tanh 软限幅 + 峰值归一 0.98），`-NoLoud` 可关。
- 实测 22% 系统音量下清晰可听；播报前脚本会自动**取消静音**（不改用户音量）。
- 若仍觉得小：`audio-env.ps1 -SetVolume -Level 0.85 -Unmute` 可临时提高系统音量再听。

## 语音后端

- 默认 **Edge 神经语音 C 云希**（`zh-CN-YunxiNeural`，男声、阳光，中英混读正常）——用户已选定为日常播报音色。
- 内置三档预设（`-Preset a|b|c`）：

  | 预设 | 音色 | 特点 |
  |---|---|---|
  | `a` | `zh-CN-XiaoxiaoNeural` | 女声，温暖 |
  | `b` | `zh-CN-XiaoyiNeural` | 女声，活泼 |
  | `c` | `zh-CN-YunxiNeural` | 男声，阳光（**默认**） |
  | `youth` | `zh-CN-YunxiNeural` + 升调 +8Hz、语速 -2%、音量 +30%、峰值归一化到 -1dB | 16–18 岁青年男声（旧默认） |
  | `manboo` | `zh-CN-XiaoyiNeural` + 升调 +30Hz、语速 +2% | **新默认**：参考用户提供的 ManBoo 样本（F0≈329Hz 的明亮年轻女声），更有起伏、不冰冷 |
  | `c` | `zh-CN-YunxiNeural` | 男声，阳光（备用） |

  查看映射：`voice-edge-tts.ps1 -ListPresets`；完整音色表：`-ListVoices`。
  用法：`voice-edge-tts.ps1 -Preset youth -Text "..."`；`voice-notify.ps1 -Preset youth -File x.txt`。
- Edge 失败（断网/超时）→ 自动回退 **离线 Piper 中英混读**（`voice-offline.ps1`），任务不中断。
- 播放链路：Edge 输出 MP3 → Python `soundfile` 解码成 WAV → `SoundPlayer` 播放（避免 MP3 播放器变调）。

## 失败处理

- 播报失败只写一行日志，不影响任务完成判定；不要把"播报失败"当阻塞上报。
- 同一任务重复完成只播一次（确认收尾前只调一次）。
- **听不见时先体检**：`powershell -File scripts/audio-env.ps1` 看默认播放设备/系统音量/静音；
  音量太低就 `-SetVolume -Level 0.85 -Unmute`（本机曾因系统音量仅 22% 导致“念了但听不见”）。
