# Grow Me · 让 AI 干活不偷懒，也不空转

> **先问清 → 先落盘 → 再动手；上下文只留结论，细节去文件里取。**
> 一个「常驻工作协议」技能：装上即对所有动手类任务生效，不必每次点名。

- 当前版本：**V1.6.0**（见 [CHANGELOG.md](CHANGELOG.md)）
- 许可：[MIT](LICENSE)
- 技能本体：[`grow-me/`](grow-me/)（`SKILL.md` + `references/` + `scripts/` + `evals/`）

## 它解决什么问题

| 你遇到的现象 | 对应规则 |
|---|---|
| 需求没问清楚就开做，返工三轮 | 规则三 追问闸门（设计树 + 前沿轮次，≤5 问、每题带默认值） |
| 说"已完成"但没跑过、没证据 | 规则四 五维工件 + 规则六 证据收尾 |
| 上下文被翻烂、token 烧光 | 规则一 自动落盘 + 规则二 上下文纪律 |
| 一轮就交，bug 留给用户 | 规则七 自动测试轮次（提交给自己 → 自审 → 自试 → 择优修） |
| 多个窗口各写各的、文档没人看 | 规则八 多 Agent 总线（Webhook + 回执 + 催办） |
| 不知道 AI 有没有在说谎、训练 loss 卡住 | 规则九 只读监测台（8176 + 定位仪 + 证据台账 + Loss 工作台） |

## 九条规则

1. **自动落盘**：先建 `.grow-me/<日期>-<slug>.md` 七节工作记录，再动手；长输出落 `logs/`，交付物先成文件。
2. **上下文纪律**：先检索后精读、单次 ≤200 行、有目的才读、已读不重读、不 echo 大段内容。
3. **追问闸门**：事实自查 / 可逆假设自定 / 决策才问；一轮 ≤5 问，每题带默认值，不回即按默认推进。
4. **五维工件**：Harness（验证命令清单）/ Graph（任务 DAG）/ Prompt（节点 3 行规格）/ Context（事实节）/ Loop（预算）。
5. **循环与刹车**：计划→动作→观察→验证→修正；每节点 ≤10 次调用、≤2 次重试；失败换假设，不原地打转。
6. **证据收尾**：进度图 / 本轮 / 证据 / 下一步 / 阻塞 + 记录路径；达标即停。
7. **自动测试轮次**：用户说"可以自动化测试几轮"即放行，跑 N 轮自提交-自审-自试；用户插话立即停并落盘。
8. **多 Agent 总线**：`send / inbox / read / ack / pending / nudge / verify / wait`，文档只传路径+sha1+摘要，没 ack 不算完成。
9. **监测台与定位仪**：接手后立刻起只读监测台（默认 `127.0.0.1:8176`，占用自动 +1）→ 扫描本机 AI → 给自己装定位仪（`beacon.mjs`）上报心跳与证据；**只观察"谁在线、它的话有多少条有证据"，不控制任何 AI**。持证 = 装了 grow-me 且版本一致。

## 安装

### 方式 A：克隆仓库（推荐）

```powershell
git clone https://github.com/dl4171503-ll12/Grow-ME.git
Copy-Item .\Grow-ME\grow-me "$env:USERPROFILE\.agents\skills\" -Recurse -Force
```

Linux / macOS：

```bash
git clone https://github.com/dl4171503-ll12/Grow-ME.git
cp -r Grow-ME/grow-me ~/.agents/skills/
```

### 方式 B：手动复制

把 [`grow-me/`](grow-me/) 整个目录放进 `~/.agents/skills/`（Codex / DSH / Cursor 等兼容 `.agents/skills` 的客户端都适用）。

### 方式 C：只想常驻规则

把 [`grow-me/references/porting.md`](grow-me/references/porting.md) 里的 6 条粘进项目 `AGENTS.md` / `CLAUDE.md` / `.cursor/rules`，不必装技能。

### 验证安装

```powershell
node grow-me/scripts/validate-skill.mjs grow-me
# 期望输出: RESULT: PASS
```

## 多 Agent 总线（规则八）

多个独立窗口 / 独立 agent 互相通信，不再"各写各的"：

```powershell
# 一个窗口起服务（零依赖，只绑本机）
node grow-me/scripts/bus.mjs serve
# 各窗口登记
node grow-me/scripts/bus.mjs register --agent win-a --label 窗口A
# 交接（消息五要素：谁→谁 / 要做什么 / 依据 / 时限 / 回执要求）
node grow-me/scripts/bus.mjs send --from win-a --to win-b --kind handoff `
  --topic "交接：接口规范" --body "请读 docs/api.md，回执：同意哪几条、补哪一条" --ref docs/api.md
# 接收方：verify → read → ack → 回信
node grow-me/scripts/bus.mjs verify --id <id>
node grow-me/scripts/bus.mjs ack --id <id> --by win-b --note "同意，补充：错误码分 4xx/5xx"
```

数据默认在 `~/.grow-me/bus`，端口 `127.0.0.1:8787`（被占用自动 +1，实际端口见 `runtime.json`）。

## 监测台与定位仪（规则九，只读）

接手 skill 后自动做四件事：起监测台、扫本机 AI、装定位仪、把"已完成"写成证据。
**监测台只读观察，不控制任何 AI。**

```powershell
node grow-me/scripts/console.mjs            # 默认 127.0.0.1:8176，被占自动 +1；端口见 ~/.grow-me/console/runtime.json
node grow-me/scripts/scan-ai.mjs            # 只看扫描结果（JSON）
node grow-me/scripts/beacon.mjs register --agent win-a --model deepseek-flash   # 装定位仪（报到）
node grow-me/scripts/beacon.mjs watch --agent win-a --every 30                 # 保活心跳
node grow-me/scripts/beacon.mjs claim --agent win-a --claim "P1 完成，loss 8.61" --evidence "runs/p1-s1/train.log:100"
```

- 页面四个面板：**定位仪**（谁在线、技能版本、持证/未持证、证据通过率）、**AI 扫描**（哪些装了 grow-me）、
  **证据台账**（无证据 = 未验证 = 视同说谎，顶部红色计数）、**Loss 工作台**（瞎猜线 8.76 / 目标 2~3 / 备份清单）。
- **持证才干活**：装了 grow-me 且版本一致 = 绿；未持证 = 红，不得代表 skill 交付。
- 训练任务把 `step,loss,phase,sub` 写进 `.grow-me/loss/loss.csv`，工作台自动画曲线；
  minmind 预训练按 [`grow-me/references/minmind-training.md`](grow-me/references/minmind-training.md) 的
  6 阶段 × 3 子阶段规范执行，每段结束存 `runs/pX-sY/`。

## 自动测试轮次（规则七）

说「**你可以自动化测试几轮**」= 同时放行，不再每轮问。每轮产物写 `.grow-me/rounds/<slug>-rN.md`（提交物 / 验收命令 / 自审发现 / 自试发现 / 修法择优），最后给轮次汇总表。
同一 bug 连修 2 轮仍红 → 停手上报；**用户发来新消息 → 立刻停**并汇报当前状态。

## 仓库结构

```
Grow-ME/
├── grow-me/                  # 技能本体（复制这个目录到 ~/.agents/skills/）
│   ├── SKILL.md
│   ├── references/           # 追问/五维/落盘/轮次/总线/监测台/训练/来源
│   ├── scripts/              # console.mjs 监测台、beacon.mjs 定位仪、scan-ai.mjs 扫描、bus.mjs 总线、validate-skill.mjs 校验
│   ├── evals/evals.json      # 回归用例
│   └── LICENSE
├── scripts/                  # 仓库级工具（发布、打包）
├── .github/workflows/        # CI：每次 push/PR 自动校验
├── README.md  CHANGELOG.md  CONTRIBUTING.md  RELEASE.md  VERSION
```

## 发布与版本（维护者）

**发布新版本的第一件事：先更新本仓库，再更新本机安装副本。**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version V1.6.1
```

脚本会：校验 `VERSION` 与 `SKILL.md` 一致 → 跑 `validate-skill.mjs` → 提交 → 打 tag → **推送仓库** → 提示同步本机副本。完整清单见 [RELEASE.md](RELEASE.md)。

## 共创

- 提 Issue / PR 前请读 [CONTRIBUTING.md](CONTRIBUTING.md)
- PR 必须通过 CI（`validate-skill.mjs`）且说明「解决了什么现象、对应哪条规则」
- 改动规则语义（尤其红线）需要 Issue 讨论后再提 PR

## 致谢

追问机制参考 Matt Pocock 的 grilling / `matt-riley/agent-skills` 的 grill-me（MIT）；技能结构参考 Anthropic `skill-creator` 与 Codex `create-skill`。详见 [`grow-me/references/sources.md`](grow-me/references/sources.md)。
