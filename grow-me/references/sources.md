# 来源、致谢与版本记录

## 这个 skill 是什么

`grow-me` 是一份**常驻工作协议**，不是工具封装。装上后对所有"动手类"任务生效，做三件事：

1. **先问清**：用设计树前沿轮次把需求追问到不需要猜。
2. **先落盘**：工作状态写进 `.grow-me/` 记录，上下文只留结论 —— 这是省 token 的根基。
3. **再动手**：五维工件 + 预算化循环 + 证据收尾，反偷懒也反空转。

## 术语说明（诚实声明）

`harness engineering`、`graph engineering`、`prompt engineering`、`context engineering`、`loop engineering`
没有统一行业定义，属于围绕 AI agent 工作方式的工作性提法。本 skill 把它们落成可执行动作：

| 提法 | 本 skill 中的落地含义 |
|---|---|
| Harness engineering | 把"可验证"变成硬前提：验证命令清单、最小验证、真实执行证据 |
| Graph engineering | 把任务当 DAG：节点可验证、边是依赖、标并行、按拓扑序推进 |
| Prompt engineering | 每个节点写成可判定规格：目标 / 约束 / 验收 |
| Context engineering | 省上下文：检索优先、不重读、带行号引用、状态外置到记录 |
| Loop engineering | 给循环装刹车：固定五步 + 每节点预算 + 失败升级 + 达标即停 |

## 借鉴的上游

- **grill-me**（设计树 + 前沿轮次 + "事实归自己、决策归用户"）：Matt Pocock 的 `grilling` 思路，
  实现见 `matt-riley/agent-skills` 的 `skills/grill-me` 与 `ksimback/hermes-ecosystem` 的
  `software-development/grill-me`（MIT）。本 skill 的追问协议是其裁剪改写版。
- **skill-creator**（Anthropic 官方）：技能结构、渐进式披露、描述触发原则。
  已安装于 `~/.agents/skills/skill-creator`。
- **create-skill**（本机内置）：Codex 技能目录约定与 frontmatter 规则。

## 版本记录

### V1.4.0（开源同步 + 发布流程）
- 仓库：`https://github.com/dl4171503-ll12/Grow-ME`（公开），本 skill 的版本发布以此仓库为**第一落点**。
- 新增 `RELEASE.md` / `scripts/release.ps1`：发布清单固定为「改版本号 → 跑校验 → 提交打 tag → **先推仓库** → 再更新本机安装副本」。
- 新增 `CONTRIBUTING.md`（共创规范）、`CHANGELOG.md`、GitHub Actions 自动校验（`scripts/validate-skill.mjs`）。
- 规则内容不变（V1.3.0 的八条规则与红线保持原样）。

### V1.3.0（新增多 Agent 总线）
- 规则八「多 Agent 总线（Webhook）」：本地 HTTP 服务 + 文件邮箱，`send/inbox/read/ack/pending/nudge/agents/wait` 八个动作。
- 解决三种信息孤岛：找不到人（`agents` 心跳）、发了没人看（`send` 必发通知）、看了没回执（`pending` + `nudge`）。
- 强制消息五要素：谁→谁 / 要做什么 / 依据（路径+sha1+摘要）/ 时限 / 回执要求；文档只传路径不传正文。
- 新增 `scripts/bus.mjs`（零依赖、只绑 127.0.0.1）与 `references/agent-bus.md`。
- 实测：CLI 全流程、裸 HTTP webhook（UTF-8）、pending/nudge 催办、wait 成功与超时、重复 ack 幂等、404、两窗口端到端。
- 端到端实测后补：`kind` 白名单校验（非法值 400 并列出合法值）、`requires_ack` 未给 `--by` 时自动补 30 分钟时限、
  `verify` 对无引用消息返回 `all_match:null`（区分"无引用"与"校验失败"）、客户端 3 次退避重试。

### V1.2.0（新增自动测试轮次）
- 规则七「自动测试轮次」：用户说「你可以自动化测试几轮」即放行，执行「提交给自己 → 自审 → 自试 → 择优修复」的 N 轮循环；
  默认 3 轮、最多 5 轮，同一 bug 连修 2 轮仍红则停手上报。
- 硬刹车：**用户发来新消息立刻停止轮次**（优先级高于轮数上限与"做到零问题"），当前轮落盘 + ≤8 行汇报。
- 修复择优：每个 bug 至少 2 个修法，按「影响面 / 可验证性 / 回滚成本」打分选一个并记录理由。
- 新增 `references/auto-rounds.md`：轮次文件模板、三类攻击面、择优评分、反模式、插话交互。
- 工作记录新增 `rounds/` 子目录约定；描述加入「自动化测试几轮 / 自己迭代到能用」触发词。
- 经 4 组实测（2 轮正例 / 3 轮跑满 / 用户插话打断 / 普通任务不该触发）后补：记录状态枚举加「暂停」、
  轮次状态加「中断」、明确预算按节点计算的单轮总量口径（≤25 次工具调用）。

### V1.1.0（按"常驻模式"重写）
- 明确生效范围：装上即对所有动手类任务默认生效，不再依赖点名触发。
- 新增规则一「自动落盘」：`.grow-me/<日期>-<slug>.md` 七节记录，先建记录再动手；
  长输出落 `.grow-me/logs/`；交付物先成文件；会话重启/换 agent 只读记录恢复。
- 新增规则二「上下文纪律」：禁整目录通读、禁重复读、禁 echo 大段内容、单次读 ≤200 行。
- 正文瘦身：细节全部外置到 `references/`（`context-and-docs.md`、`porting.md` 新增）。
- 收尾模板增加"记录"一行；自检清单增加记录完整性检查。
- 新增 `references/porting.md`：技能目录 / AGENTS.md 规则 / 一次性 prompt 三种接入方式。
- 经 1 次自测 + 4 次子 agent 冷启动实验（便携性 / 模糊需求 / 上下文恢复 / 无点名常驻）加固：
  追加「可逆假设」第三分类、四档开工优先级、一行紧凑提问式、SKILL.md 内联最小记录骨架、
  `.grow-me/` 落点规则、工作根/产物/下一步可执行化。

### V1.0.0（首个版本）
- Phase 0 追问闸门：一轮问整条前沿（≤5 问），每题带建议与默认值，不回即按默认推进。
- Phase 1 五维工件；Phase 2 预算化循环（≤10 次调用/节点、≤2 次重试）；Phase 3 证据收尾。
- 反偷懒红线 5 条 + 反空转红线 5 条 + 自检清单。
- `scripts/validate-skill.mjs` 自校验脚本；`evals/evals.json` 回归用例。

## 维护建议

- description 决定触发率：把用户真实说过的触发词补进去；改名影响触发，改前先想清楚。
- 红线只增不删；放松时写明理由并记进版本记录。
- 改动后跑 `node scripts/validate-skill.mjs`，必要时用 `evals/evals.json` 回归。
