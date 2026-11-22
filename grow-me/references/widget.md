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
