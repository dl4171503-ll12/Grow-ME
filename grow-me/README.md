# grow-me（技能本体）

> 本目录是 **Grow Me 技能本体**，可以直接复制到任何兼容 `.agents/skills` 的客户端里使用。
> 仓库根目录的 [`README.md`](../README.md) 讲项目定位与八条规则概览；本文件讲**这个目录里有什么、怎么用、怎么改**。

| 项 | 值 |
|---|---|
| 技能名 | `grow-me` |
| 版本 | V1.4.0（与 `SKILL.md` front matter 的 `metadata.version` 一致） |
| 类型 | `kind: policy` — 常驻工作模式，装上即对所有动手类任务默认生效 |
| 成熟度 | `maturity: stable` |
| 许可 | MIT（见同目录 [`LICENSE`](LICENSE)） |
| 依赖 | 无。纯 Markdown 规则 + 两个零依赖 Node 脚本 |

---

## 它解决什么

`grow-me` 不是"某个功能的实现"，而是一份**行为协议**：让 agent 在动手前先问清、动手时先落盘、收尾时给证据。

它盯的是三类反复出现的问题：

| 现象 | 对应规则 |
|---|---|
| 需求没问清就开做，返工三轮 | 规则三 追问闸门 |
| 说"已完成"但没跑过、没证据 | 规则四 五维工件 + 规则六 证据收尾 |
| 上下文被翻烂、token 烧光 | 规则一 自动落盘 + 规则二 上下文纪律 |
| 一轮就交，bug 留给用户 | 规则七 自动测试轮次 |
| 多个窗口各写各的、文档没人看 | 规则八 多 Agent 总线 |

## 目录结构

```text
grow-me/
├── SKILL.md                     # 技能正文与 front matter（模型读的就是它）
├── references/                  # 按需加载的细节文档（正文刻意写得省字）
│   ├── context-and-docs.md      # 工作记录模板、读回协议、反乱翻清单
│   ├── interrogation.md         # 追问闸门算法 + 五维问题库
│   ├── lenses.md                # 五维工件模板与正反例
│   ├── porting.md               # 接入其他 agent / 编辑器（AGENTS.md、规则、复制目录）
│   ├── auto-rounds.md           # 自动测试轮次：轮次模板、攻击面、择优评分、反模式
│   ├── agent-bus.md             # 多 Agent 总线：五要素、消息生命周期、催办与排障
│   └── sources.md               # 设计取舍、致谢、版本记录
├── scripts/
│   ├── bus.mjs                  # 多 Agent 总线服务端 + 客户端（零依赖）
│   └── validate-skill.mjs       # 技能自校验：结构与 front matter 检查
├── evals/
│   └── evals.json               # 8 条回归用例（看行为，不看措辞）
└── LICENSE
```

## 安装

三者任选其一，详见仓库根 [`README.md`](../README.md#安装)：

```bash
# A. 复制整个目录到技能目录（推荐）
git clone https://github.com/dl4171503-ll12/Grow-ME.git
cp -r Grow-ME/grow-me ~/.agents/skills/          # Windows: Copy-Item .\Grow-ME\grow-me "$env:USERPROFILE\.agents\skills\" -Recurse -Force

# B. 只要常驻规则，不装技能：把 references/porting.md 里的 6 条粘进 AGENTS.md / CLAUDE.md / .cursor/rules
```

装完不需要"点名"——`SKILL.md` 的 `description` 已经声明它是对所有动手类任务生效的常驻协议。

## 验证

```bash
node grow-me/scripts/validate-skill.mjs grow-me
# 期望：RESULT: PASS
```

`evals/evals.json` 是**行为**用例，不是单元测试：每条给出 `prompt`、期望表现 `expected_output` 和可判定的 `assertions`。改动 `SKILL.md` 后至少手动验证前四条（落盘、追问闸门、上下文纪律、自动轮次）。

## 规则与参考文件对照

| 规则 | 正文位置 | 细节文档 |
|---|---|---|
| 一 自动落盘 | `SKILL.md` §1 | `references/context-and-docs.md` |
| 二 上下文纪律 | §2 | `references/context-and-docs.md` |
| 三 追问闸门 | §3 | `references/interrogation.md` |
| 四 五维工件 | §4 | `references/lenses.md` |
| 五 循环与刹车 | §5 | — |
| 六 证据收尾 | §6 | — |
| 七 自动测试轮次 | §7 | `references/auto-rounds.md` |
| 八 多 Agent 总线 | §8 | `references/agent-bus.md` |
| 红线（反偷懒／反空转） | §9 | — |
| "完成"前自检清单 | §10 | — |

## 运行时产物落在哪里

| 产物 | 位置 |
|---|---|
| 任务工作记录 | `<项目根>/.grow-me/<yyyyMMdd-HHmm>-<slug>.md`（七节骨架，任务唯一真源） |
| 长输出（日志、大 diff） | `.grow-me/logs/`（正文只留 ≤5 行关键行 + 路径） |
| 自动轮次文件 | `.grow-me/rounds/<slug>-r<N>.md` |
| 总线数据 | `~/.grow-me/bus`（仅绑 `127.0.0.1`，端口默认 8787，冲突自动 +1，实际端口见 `runtime.json`） |

> 已有上层的 `.grow-me/` 时复用最近的那个，不新开——避免记录碎片化。

## 多 Agent 总线（规则八）最小用法

```bash
node grow-me/scripts/bus.mjs serve                                   # 一个窗口起服务
node grow-me/scripts/bus.mjs register --agent win-a --label 窗口A     # 各窗口登记
node grow-me/scripts/bus.mjs send --from win-a --to win-b --kind handoff \
  --topic "交接：接口规范" --body "请读 docs/api.md，回执：同意哪几条" --ref docs/api.md
node grow-me/scripts/bus.mjs verify --id <id> && node grow-me/scripts/bus.mjs ack --id <id> --by win-b --note "结论"
```

硬规则：**没有 ack 的协作等于没发生**；文档只传「路径 + sha1 + 摘要 + 期望动作」，不复制全文。

## 改这个目录之前

- 先读 [`CONTRIBUTING.md`](../CONTRIBUTING.md)：八条规则的**语义**与「反偷懒／反空转」红线属于契约，改动前先开 Issue 讨论
- 改完必须跑：`node grow-me/scripts/validate-skill.mjs grow-me`
- 版本号三处要一致：`SKILL.md` 的 `metadata.version`、仓库根 `VERSION`、`CHANGELOG.md`
- 发布流程见仓库根 [`RELEASE.md`](../RELEASE.md)（先推仓库，再更新本机安装副本）
