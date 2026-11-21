# 任务完成语音播报（规则十一）

> 目的：任务做完时，用户可能没看窗口。用一句**白话**把结果说出来；如果用户不在本窗口，就多喊两遍。

## 什么时候播

- 每个任务到达「完成判据」时（DAG 全绿 + 验收逐条有证据）→ 必须先播，再给文字收尾。
- 任务被打断/暂停/失败不上报完成 → 不播（避免误报）。

## 白话摘要怎么写（关键）

单独写成 `.grow-me/voice/<yyyyMMdd-HHmm>-<slug>.txt`，然后 `voice-notify.ps1 -File <该文件>`。

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

- **在前台** → 说 1 遍。
- **不在前台** → 前面加"提醒："并**重复 2 遍**（`-RepeatBackground` 可调），确保用户听到。
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

## 语音后端

- 默认 **Edge 神经语音**（`zh-CN-XiaoxiaoNeural`，需联网、免 Key）：`scripts/voice-edge-tts.ps1`，列出中文音色 `-ListVoices`。
- Edge 失败（断网/超时）→ 自动回退 **离线 Piper 中英混读**（`voice-offline.ps1`），任务不中断。
- 想彻底离线：`-Edge` 无此开关时可直接调 `voice-offline.ps1`；或把 `voice-notify.ps1` 里的 `$edgeScript` 换成离线脚本。

## 失败处理

- 播报失败只写一行日志，不影响任务完成判定；不要把"播报失败"当阻塞上报。
- 同一任务重复完成只播一次（确认收尾前只调一次）。
