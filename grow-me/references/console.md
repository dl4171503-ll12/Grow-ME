# 监测台与定位仪（规则九详解）

> **只读监测，不控制任何 AI。** 监测台回答两个问题：**谁在线**、**它的话有多少条有证据**。
> 定位仪 = 每个 AI 在"肚子里"报到的探针：报身份、报心跳、报声明与证据。

## 启动

```powershell
node scripts/console.mjs                 # 默认 127.0.0.1:8176
node scripts/console.mjs --port 9000     # 指定端口
node scripts/console.mjs --runs D:\runs  # 模型备份目录
node scripts/console.mjs --loss .grow-me\loss\loss.csv
```

- **端口策略**：从 8176 起，被占用就 +1，最多试 20 个；实际端口写入
  `~/.grow-me/console/runtime.json`（也会打印）。
- 数据目录：`~/.grow-me/console/`（`runtime.json` / `config.json` / `claims.jsonl` / `agents.json`）。
- 只绑 `127.0.0.1`；只读展示，**没有任何"停止/杀掉/操控 AI"的接口**。

## 定位仪（beacon.mjs）

```powershell
# 1) 报到（AI 一接手就做，表明"我是谁、我装了哪个版本的技能"）
node scripts/beacon.mjs register --agent win-a --model deepseek-flash [--cwd <dir>]

# 2) 保活心跳（长任务用；前台循环，每 30 秒一次）
node scripts/beacon.mjs watch --agent win-a --every 30

# 3) 上报声明与证据（这就是"说谎检查"的数据源）
node scripts/beacon.mjs claim --agent win-a --claim "P1-S1 完成，loss 8.61" --evidence "runs/p1-s1/train.log:100"

# 4) 上报实时消耗（说谎程度之外的"浪费"维度；建议每 ~10 次工具调用或每 5 分钟一次）
node scripts/beacon.mjs telemetry --agent win-a --tokens 84213 --waste 12040 `
  --ctx-used 45120 --ctx-max 64000 --tool-calls 37 --dup-reads 3 --dup-runs 2 --big-outputs 1

# 5) 看监测台里都有谁
node scripts/beacon.mjs status
```

定位仪上报的内容：agent 名、模型名、工作目录、PID、**技能版本与安装路径**、心跳时间；
telemetry 额外上报：累计 tokens、浪费 tokens、上下文已用/上限、工具调用数、重复读/重复跑/超大输出次数。

监测台据此判断：

| 判断 | 规则 |
|---|---|
| 在线 / 离线 | 最后心跳 < 90 秒 = 在线 |
| 持证 / 未持证 | 上报了 `skill_version`（且非 unknown）= 持证 |
| 版本一致 | 与监测台所在技能的版本比对，不一致标黄"版本不符" |
| **说谎程度** | 该 agent 未验证声明 ÷ 声明总数（≥30% 标红） |
| **浪费率** | 浪费 tokens ÷ 累计 tokens（≥20% 标红） |
| **上下文占用** | ctx_used ÷ ctx_max（≥85% 标红，65~85% 标黄） |

> **持证才干活**：装了 grow-me 且版本一致的 AI 才标绿；未持证的 AI 不得代表 skill 交付。
> 判据不是它自称，而是它能不能报出自己的技能版本 + 每条声明有没有证据 + 消耗是否合理。

**浪费 tokens 怎么算**：重复读同一文件、重复跑同一命令、把大段输出贴回上下文、非必要验证——
这些操作消耗的 token 记进 `--waste`。上报是自报，但监测台会把它和"重复读/重复跑/超大输出"次数并列显示，
自报和计数对不上就是可疑。

## 四个面板

### 1) 定位仪（谁在干活 / 是否持证）

- 在线状态、模型、技能版本（绿=持证、黄=版本不符、红=未持证）、工作目录、最后心跳、证据通过率。
- 空表提示：`node scripts/beacon.mjs register --agent <id> --model <name>`。

### 1.5) 实时消耗 / 说谎程度（谁在烧 token、谁在糊弄）

- 每行一个 agent：**说谎程度**（未验证声明占比）、**上下文占用**（进度条 + 已用/上限）、
  **累计 tokens**、**浪费 tokens（%）**、工具调用、**重复读/重复跑/超大输出**次数、标记（上下文将满/浪费高/说谎率高）。
- 顶部徽章：全局说谎率、全局浪费率（所有 agent 的浪费 tokens ÷ 累计 tokens）。
- 数据来源：`beacon.mjs telemetry` 上报 + `/api/telemetry`；历史保留最近 240 个点。

### 2) 证据台账（说谎检查）

- 每条记录：时间 / 来源 agent / 声明 / 证据 / 判定（已核验 / **未验证**）。
- 顶部红色徽章显示"未验证声明: N"——**N > 0 就说明有 AI 在拿没证据的话交差**。
- 无 evidence 的声明一律标红，不因为"它说得很像真的"而放行。

### 3) Loss 工作台

- 数据文件 `.grow-me/loss/loss.csv`，每行 `step,loss[,phase,sub]`。
- **瞎猜线 8.76** = `ln(词表大小)`（6400 词表 ≈ 8.76）：模型没学时交叉熵就在这条线附近。
- **目标区间 2~3**：loss 掉到这里说明预训练确实学到了结构。
- 阈值可在页面改，或 `POST /api/loss/config`。

### 4) 本机 AI 扫描

`scripts/scan-ai.mjs`：按 PATH 命令 / 安装目录 / 运行进程三类证据识别 AI，并标注是否装了 grow-me。
新增 AI：在 `KNOWN` 数组加一条 `{name, kind, cmds, exe, dirs, procs, skillRoots}` 即可。

## API 速查

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 监测台页面 |
| GET | `/api/status` | 总览：端口 / AI / 定位仪 / 台账 / loss / 备份 |
| GET | `/api/ai` | 重新扫描本机 AI |
| GET | `/api/agents` | 定位仪列表（在线、持证、心跳、证据统计） |
| POST | `/api/beacon` | 定位仪报到/心跳 |
| POST/GET | `/api/telemetry` | 上报实时消耗 / 查询历史点（`?agent=<id>`） |
| GET/POST | `/api/claims` | 读台账 / 登记声明+证据 |
| GET | `/api/loss` | loss 点 + 统计 + 配置 |
| POST | `/api/loss/config` | 改瞎猜线 / 目标区间 |
| GET | `/api/checkpoints` | 模型备份清单 |

## 故障排查

| 现象 | 处理 |
|---|---|
| 端口不是 8176 | 被占用，看 `runtime.json` 或 `--port` 指定 |
| 定位仪报 `cannot reach` | 监测台没起：先 `node scripts/console.mjs` |
| agent 一直"离线" | 心跳没跑：用 `beacon.mjs watch --every 30` |
| 显示"未持证" | 该 AI 没上报技能版本：确认它真的装了 grow-me（`~/.agents/skills/grow-me`） |
| 未验证一直是 N | 正常，说明 AI 还没给证据；让它 `beacon.mjs claim ... --evidence ...` |
| loss 无数据 | 检查 `.grow-me/loss/loss.csv`，格式 `step,loss` 开头 |
