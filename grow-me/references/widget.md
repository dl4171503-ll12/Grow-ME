# 悬浮组件条（规则十二）

> 类似微信输入法的移动组件条：常驻最前、可拖拽、按钮发消息、麦克风录一句就发。

## 启动

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/widget.ps1
```

- 无依赖、纯 WPF（PowerShell 自带）；窗口 `Topmost=True`，可在任何应用最前端浮动。
- **默认缩成小球**（30px，绿色 "G"）；点小球展开成完整条；条上的 `X` 收回小球；右键小球/条 → 菜单"退出"才是关闭。
- 小球和条都能按住拖拽到屏幕任意位置；位置与折叠状态自动记住（`~/.grow-me/widget/pos.json`、`state.json`），并限制在屏幕工作区内（不会盖住任务栏）。
- **跟随虚拟桌面**：看门狗每 1.2 秒置顶一次，并用 `IVirtualDesktopManager` 把窗口移到当前桌面 —— 效果等价于"在所有桌面显示此窗口"（切到哪个桌面都能看到它）。

## 按钮（接口控制）

按钮与要发送的文字在 `scripts/widget-commands.json` 里配置，默认：

| 按钮 | 发送内容 |
|---|---|
| 说中文！ | `说中文！` |
| 有 bug 重新改 | `有 bug 重新改` |
| 继续工作 | `继续工作` |
| 停一下: | `停一下:` |
| 说大白话！ | `说大白话！` |

点击后：把文字放进剪贴板 → 激活 `DeepSeek Harness` 窗口 → `Ctrl+V` → `Enter`，即**直接作为一条消息发进当前会话**（DSH 没有公开的消息 API，所以用窗口级自动化；需要 DSH 窗口存在）。

## 语音录入

1. 点 `Mic` → 开始录音（16 kHz / 16-bit / 单声道，最长 60 秒），按钮变 `Stop`；
2. 再说一次 → 停止录音，保存到 `~/.grow-me/widget/rec/rec-<时间>.wav`；
3. **本地识别**：`widget-asr.ps1` 用 Windows SAPI 离线 zh-CN 识别器把 WAV 转文字（免费、不联网）；
4. 识别结果直接发进会话；识别为空时发送 `[voice] 本地识别为空，音频文件: <路径>`，把音频路径也带上；
5. 发送成功会用 youth 音色播报"已发送"（短促，不打断）。

## 响应体验

- 识别在本地完成（SAPI，秒级），发送是剪贴板+回车，链路里没有云端 ASR 往返，延迟低；
- 语音播报用已调好的 Edge youth + 响度最大化（见 `voice-report.md`），22% 系统音量也能听清；
- 我（agent）收到消息后按规则十一在收尾时用白话播报结果。

## 局限（诚实说明）

- DSH 没有公开消息 API，发送依赖窗口自动化：DSH 必须开着且窗口存在；若窗口找不到，状态栏显示 `no window`。
- 录音走默认麦克风（当前是 `麦克风阵列`）；环境嘈杂时 SAPI 识别率会下降，此时会发送音频路径供排查。
- 组件条不监听全局快捷键；需要的话可加。

## 常驻最前与多桌面（V1.10.3）

- **看门狗**：每 1.2 秒把窗口重新置顶（`SetWindowPos(HWND_TOPMOST, SWP_NOMOVE|NOSIZE|NOACTIVATE)`），所以即使别的程序也是置顶窗口，组件条也会被抬回最前，且不抢焦点。
- **跟随虚拟桌面**：用 `IVirtualDesktopManager` 检测；当组件条不在当前桌面时，取前台窗口所在桌面 GUID，把组件条 `MoveWindowToDesktop` 过去 —— 切桌面（Win+Ctrl+←/→）后组件条会跟到当前桌面。
- **局限**：独占全屏游戏 / 安全桌面（UAC）覆盖不了；若需要盖住"以管理员身份运行"的窗口，请以管理员身份启动组件条。

## 定向发送（多会话 / 多窗口，V1.10.5）

点按钮时只发给**一个**目标窗口，不会群发：

1. 目标选择：当前前台窗口若是 DSH → 就发给它；否则用**最近一次前台过的 DSH 窗口**（组件条每 1.2 秒记录一次）；都没有才退到第一个 DSH 窗口。
2. 发送前会把目标窗口激活，并点击该窗口**底部居中的聊天输入区**让输入框聚焦，再粘贴 + 回车；
3. 日志写明实际目标：`sent to [创建 grow me 技能 V1.0.0 — DeepSeek Harness]: 说中文！`

注意：这是**窗口级**定向；同一窗口里的多个会话标签页以 DSH 当前激活的那个为准（不替你切换标签）。

## 单实例（永远只保留最新，V1.10.6）

- **每次启动都会先清掉所有旧组件条进程**（按命令行 `-File ...\widget.ps1` 精确匹配，不会误杀别的 PowerShell），然后抢命名互斥锁 `Local\GrowMeWidgetSingleton`；抢到才继续启动。
- 启动时写 `~/.grow-me/widget/instance.json`（pid + buildHash + 启动时间）；`buildHash` = `widget.ps1 + widget-native.ps1 + widget-commands.json` 的 SHA256。
- 所以只要**内容有改动**（改脚本/改按钮配置）再启动一次，旧版会被立刻关掉、由新版覆盖；重复启动也只会留下一个。
- 清理遗留实例：`powershell -File tools/widget-kill.ps1`（kit 工具）；查看数量：`tools/widget-count.ps1`。
- 已处理“旧进程被强杀后互斥锁变成 Abandoned”的情况（捕获 `AbandonedMutexException` 视为拿到锁）。

## 为什么之前按钮没用（V1.10.7 修复）

- 现象：日志写 `sent`，但聊天里什么都没收到。
- 根因：DSH 窗口当时在**另一个虚拟桌面**（DWM `cloaked=2`），`SetForegroundWindow` 失败，点击/粘贴落到了前台别的程序（例如 Edge）里。
- 修复：发送前先 `IVirtualDesktopManager.FollowCurrent` 把目标 DSH 窗口拉到当前桌面 → 再激活 → **校验前台句柄确实是目标窗口**；不是就中止并写日志 `abort: target not foreground`，绝不往别的窗口乱贴。

## 语音识别故障排查（V1.10.7）

- 录音**自动增益**：内置麦克风阵列电平很低（可能只有满幅 0.1%），录制结束会自动放大到约 90% 满幅（最多 40 倍），再交给 SAPI。
- ASR 三连：先识别原始 WAV，失败再试峰值归一版、再试压缩版；日志会写 `asr(raw|peak|compressed): 文字` 或 `asr: empty`。
- 麦克风状态：`audio-env.ps1 -Capture` 查看默认麦克风音量/静音，`-Capture -SetVolume -Level 1.0 -Unmute` 拉满。
- 局限：Windows SAPI 离线识别是中小模型，长句/口音/嘈杂环境准确率一般；要更高准确率可换在线 ASR（需 API）或 Whisper（本地大模型，需额外安装）。

## 语音识别（V1.10.8：默认换成本地 Whisper）

- **默认识别引擎：faster-whisper（离线、CPU、int8）**，中文准确率远高于 Windows SAPI；
  模型 `base` 放在 `%USERPROFILE%\.grow-me\asr\faster-whisper-base`（约 138 MB）。
- 安装/换模型：`powershell -File scripts/asr-setup.ps1 -Model base|small`（自动 pip 安装 + 从 hf-mirror 下模型）。
- 识别链路：Whisper 优先 → 失败才回退 Windows SAPI（raw/peak/压缩三连）；日志写 `asr(whisper): 文字`。
- 实测对比（同一段 9.4s 录音）：
  - SAPI：`我现在正在涌现`
  - Whisper：`我现在正在用这个控制条尝试录音你能不能听到?`（含模型加载总耗时约 2.8s）
- 局限：Whisper base 对很快/很轻的口音仍会错几个字；要更准可换 `small`（约 466 MB，慢一些）。

## 故障排查

- 点按钮没反应 / 组件条消失过：先看日志 `~/.grow-me/widget/widget.log`（V1.10.2 起所有按钮/录音异常都写日志，不再崩掉整个组件条）。
- 日志出现 `send: clipboard fail`：剪贴板被别的程序占用；脚本已自动重试 3 次，仍失败就稍后再点。
- 日志出现 `focus mismatch`：DSH 窗口没抢到前台（可能被系统焦点保护拦住），再点一次通常即可。
- `no harness window`：DSH 没开或窗口最小化到托盘；打开主窗口再点。
- 日志出现 `sent: ...` 但聊天里没有：检查是否发到了别的输入框；点一下 DSH 输入框再重试。

## 相关文件

| 文件 | 作用 |
|---|---|
| `scripts/widget.ps1` | WPF 悬浮条主程序（按钮/拖拽/录音/发送/播报） |
| `scripts/widget-native.ps1` | winmm 录音 + 窗口激活的原生封装 |
| `scripts/widget-asr.ps1` | 本地 SAPI 识别 WAV → 文字 |
| `scripts/widget-commands.json` | 按钮与文案配置 |
| `scripts/voice-edge-tts.ps1` | 播报用的 Edge TTS（youth 预设） |
