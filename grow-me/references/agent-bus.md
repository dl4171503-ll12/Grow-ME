# 多 Agent 总线（grow-me 规则八详解）

> 多个独立窗口 / 独立 agent 协作时，用本地 Webhook + 文件邮箱互相发消息、要回执、催办。
> 核心目标：**消灭三种信息孤岛** —— 找不到人、发了没人看、看了没回执。

## 为什么需要它

跨 agent 协作最常见的三种死法：

1. **找不到人**：A 不知道 B 在哪个窗口、叫什么、还在不在。
2. **发了没人看**：A 写了文档，以为 B 会看见；B 根本不知道有这东西。
3. **看了没回执**：B 看了但没说，A 一直等，最后两人各写一套。

总线把这三件事分别变成可查询、可检测、可催办的动作。

## 架构

```
┌──────────┐   HTTP POST /send      ┌────────────────────┐
│ 窗口 A     │ ─────────────────────► │  bus.mjs serve      │
│ (agent-a) │ ◄───────────────────── │  127.0.0.1:8787     │
└──────────┘   GET /inbox            │  文件邮箱 + 注册表   │
┌──────────┐                         │  ~/.grow-me/bus/    │
│ 窗口 B     │ ◄────────────────────► │                     │
│ (agent-b) │   POST /ack /nudge      └────────────────────┘
└──────────┘
```

- 只有 `bus.mjs` 一个文件，零依赖，默认只绑 `127.0.0.1`。
- 数据：`agents.json`（谁在线）、`messages/<to>/<id>.json`（消息）、`runtime.json`（URL/端口）。
- 两边共享同一个文件系统时，文档只需传路径；不共享时（跨机器）才需要传内容。

## 快速开始

```bash
# 1) 起服务（一个窗口起一次即可）
node scripts/bus.mjs serve

# 2) 各自登记
node scripts/bus.mjs register --agent win-a --label 窗口A
node scripts/bus.mjs register --agent win-b --label 窗口B
node scripts/bus.mjs agents                       # 看谁在线（5 分钟心跳）

# 3) A 交接文档给 B
node scripts/bus.mjs send --from win-a --to win-b \
  --topic "交接：接口规范" --kind handoff \
  --body "请读 docs/api.md，回执：是否同意第 3 条，并补充你那边的差异" \
  --ref docs/api.md --requires-ack true --by 2026-11-10T23:30:00+08:00

# 4) B 先校验引用没被改，再读、再回执
node scripts/bus.mjs verify --id <id>            # refs 的 sha1 是否仍与发送时一致
node scripts/bus.mjs inbox --agent win-b
node scripts/bus.mjs read --id <id> --by win-b
node scripts/bus.mjs ack  --id <id> --by win-b --note "同意，补充：错误码要区分 4xx/5xx"
node scripts/bus.mjs send --from win-b --to win-a --kind reply --body "同意 + 1 条补充"

# 5) A 等回执 / B 等新消息
node scripts/bus.mjs wait --agent win-a --timeout 60
node scripts/bus.mjs wait --agent win-a --id <id> --timeout 60   # 等某条被 ack
```

## 消息五要素（必须齐）

| 要素 | 写法 | 缺了会怎样 |
|---|---|---|
| 谁→谁 | `--from` / `--to` | 对方不知道是不是给自己 |
| 要做什么 | `--body` 第一句用动词开头 | 对方只能"知道了"，不会动 |
| 依据 | `--ref <path>`（自动带 sha1）+ 3 行摘要 | 对方不知道读哪个版本 |
| 期望时限 | `--by <ISO>` | 无期限 = 无限期（未填时自动补 30 分钟） |
| 验收方式 | body 里写"回执要回答什么" | 回执变"收到"两字 |

模板：

```
【交接】<对象>：<一句话结论>
依据：<路径>（sha1 <前 12 位>）
请你：1) <动作 1> 2) <动作 2>
回执要求：<必须回答的点>，<时限>
```

## 生命周期

```
unread ──read──► read ──ack──► acked
   │                              ▲
   └──────── nudge（催办）────────┘
```

- `read` 只表示"看了"，**不算完成**；`acked` 才表示"处理并回复了"。
- `verify --id <id>` 校验 refs 的 sha1：文档在发送后被改过（或路径失效）会返回 `all_match:false`，
  此时先回执要新版本，不要按旧引用执行。
- `pending --agent x --minutes N` 列出超过 N 分钟仍未 ack 的消息 —— 这就是"对方不看"的检测器。
- `nudge --id <id>` 生成一封催办消息；仍不回就按升级阶梯处理。

## 找人与看不到人

- `agents` 返回每个 agent 的 `online`（`last_seen` 5 分钟内）。
- 离线：换一个在线 agent，或把交接内容写进 `.grow-me/` 并在主记录里标「未回执，交接物在 X」。
- 永远不要"假设对方看到了"。

## 升级阶梯（对方不回）

| 次数 | 动作 |
|---|---|
| 1 | `pending` 确认确实没 ack |
| 2 | `nudge` 催办（附原消息 id） |
| 3 | 把未回执情况写进 `.grow-me/` 主记录，向用户报「X 未回执，交接物在 Y」 |
| 4 | 若任务可继续，按默认假设推进，并在记录里标「假设对方同意」 |

## 并发与顺序

- 每条消息一个文件，多 agent 同时发不会互相覆盖。
- `ack` 幂等：重复 ack 不会坏数据。
- 同一文档多人改：各自 append 自己的小节（`## 回执意见 — win-b`），不要整篇重写。
- 消息 id 写进 `.grow-me/` 主记录的「协作」小节，方便回查。

## 安全

- 默认 `127.0.0.1`，不对外暴露。需要跨机器时用 `--host 0.0.0.0` + 内网/防火墙，**不要裸奔公网**。
- 消息里不放密钥、令牌、个人信息；文档引用传路径，不传正文。
- 客户端必须 UTF-8：`curl --data-binary @file`；PowerShell 用
  `[System.Text.Encoding]::UTF8.GetBytes($json)`，否则中文会变 `????`。

## 故障排查

| 症状 | 原因 / 处理 |
|---|---|
| `cannot reach bus ...` | 服务没起：`node scripts/bus.mjs serve`；或 `--url` 指错端口 |
| 端口被占 | 服务会自动 +1 重试，实际端口看 `~/.grow-me/bus/runtime.json` |
| 中文变 `????` | 客户端没发 UTF-8 字节（见上） |
| 收不到消息 | `--to` 的 agent 名要和对方 `register` 的一致；`inbox` 默认返回全部 |
| `pending` 一直有 | 对方没 ack——用 `nudge`，别自己猜 |

## 反模式

1. **只把文件丢进仓库，不发消息** —— 对方根本不知道。
2. **发"在吗/看一下"** —— 没有五要素，等于制造噪音。
3. **正文贴整篇文档** —— 应该发路径 + 摘要。
4. **没有 ack 就宣布完成** —— 协作等于没发生。
5. **高频轮询** —— `wait` 内部 1 秒一次，别自己写死循环。
6. **多个问题拆成十几条消息** —— 一条消息列清单，省对方上下文。
