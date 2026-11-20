# 控制台（规则九详解）

> 接手 grow-me 后第一件事：起控制台、扫 AI、把"已完成"变成可核查的证据。
> 控制台是本地单页 Web 应用，零依赖，只绑 `127.0.0.1`。

## 启动与端口

```powershell
node scripts/console.mjs                 # 默认 127.0.0.1:8176
node scripts/console.mjs --port 9000     # 指定端口
node scripts/console.mjs --runs D:\runs  # 指定模型备份目录
node scripts/console.mjs --loss .grow-me\loss\loss.csv
```

- **端口策略**：从目标端口开始，被占用就 +1 重试，最多试 20 个；实际端口写入
  `~/.grow-me/console/runtime.json`（同时打印到 stdout）。
- 状态目录：`~/.grow-me/console/`（`runtime.json` / `config.json` / `claims.jsonl`）。
- 不要把端口开到公网；需要远程时用 SSH 隧道，而不是 `--host 0.0.0.0`。

## 三个能力

### 1) 本机 AI 扫描（`GET /api/ai`）

`scripts/scan-ai.mjs` 会按三类证据识别 AI：

| 证据 | 例子 |
|---|---|
| PATH 命令 | `where codex` / `where claude` / `where ollama` |
| 安装路径 | `%LOCALAPPDATA%\Programs\cursor`、`~/.codex`、`~/.claude`、`~/.ollama`、`~/.dsh` |
| 运行进程 | `tasklist` 里出现 `Cursor.exe` / `codex` / `ollama` |

对每个识别到的 AI，再检查它的配置目录或全局技能目录里有没有 grow-me，给出 `skillInstalled` 与 `skillPaths`。
新增 AI：在 `scan-ai.mjs` 的 `KNOWN` 数组里加一条 `{name, kind, cmds, exe, dirs, procs}`。

### 2) 证据台账 / "AI 有没有说谎"（`/api/claims`）

```powershell
# 登记一条声明（有 evidence = 已核验）
curl.exe -X POST http://127.0.0.1:8176/api/claims -H "content-type: application/json" `
  -d '{\"claim\":\"预训练完成，loss 2.41\",\"evidence\":\"runs/p1-s2/validator.log: 2.41\"}'
```

- 判定规则：`evidence` 为空 → **未验证**（面板标红，等于"可疑"）；有命令输出/文件行号 → 已核验。
- 这就是"检查 AI 有没有说谎"的落地：**不是信它的措辞，是看它敢不敢给证据**。
- 规则九要求：任何"已完成/已修复/已达标"都必须有一条 claim + evidence。

### 3) Loss 工作台（`/api/loss`）

数据文件：`.grow-me/loss/loss.csv`，每行 `step,loss[,phase,sub]`，例如：

```csv
step,loss,phase,sub
100,7.94,1,1
200,7.10,1,1
...
1800,2.41,6,3
```

- 面板自动画曲线，并叠加两条参考线：
  - **瞎猜线 = 8.76**：等于 `ln(词表大小)`，以 6400 词表为例 `ln(6400)≈8.76` —— 模型没有学习时
    交叉熵就是"均匀瞎猜"的水平。
  - **目标区间 2~3**：loss 降到 2~3 说明预训练确实学到了结构（具体值随数据/词表/模型规模变化）。
- 改阈值：`POST /api/loss/config {line, targetLow, targetHigh}`；面板上也能直接改。
- 阶段边界：CSV 里 `phase` 变化处会画竖线，对应 6 个训练阶段。

### 4) 模型备份清单（`/api/checkpoints`）

扫描 `--runs` 目录（默认 `./runs`），列出每个备份的名字、时间、文件数、大小。
训练脚本要按 `runs/p<阶段>-s<子阶段>/` 命名，配合 minmind 规范见
[minmind-training.md](minmind-training.md)。

## API 速查

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 控制台页面 |
| GET | `/api/status` | 总览：端口/AI/台账/loss/备份 |
| GET | `/api/ai` | 重新扫描本机 AI |
| GET/POST | `/api/claims` | 读台账 / 登记声明+证据 |
| GET | `/api/loss` | loss 点 + 统计 + 配置 |
| POST | `/api/loss/config` | 改瞎猜线/目标区间 |
| GET | `/api/checkpoints` | 模型备份清单 |

## 故障排查

| 现象 | 处理 |
|---|---|
| 端口不是 8176 | 被占用了，看 `runtime.json` 里的实际端口，或 `--port` 指定 |
| 页面空白 | 确认 `scripts/console.html` 与 `console.mjs` 同目录 |
| AI 扫描为空 | 该机器没有已知客户端，或安装路径不在 `KNOWN` 里；按需扩展 |
| loss 无数据 | 检查 `.grow-me/loss/loss.csv` 是否存在、格式是否 `step,loss` 开头 |
| 台账不显示 | 刷新页面；数据在 `~/.grow-me/console/claims.jsonl` |
