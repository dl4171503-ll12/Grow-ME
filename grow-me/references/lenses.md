# 五维工件模板（grow-me Phase 1 详解）

> 每个维度都要留下"能贴出来"的实物。下面是模板与正反例，按任务规模取用，别为了填表而填表。

## 1. Harness Engineering — 验证清单

**先找命令，再写代码。** 命令来源的优先级：

1. `package.json` 的 `scripts`（Node）
2. `Makefile` / `justfile` / `Taskfile.yml`
3. `pyproject.toml` / `tox.ini` / `noxfile.py`（Python）
4. `Cargo.toml` / `go.mod` / `pom.xml` / `build.gradle`
5. CI 配置（`.github/workflows/*.yml`、`.gitlab-ci.yml`）—— 最权威，因为它是必须通过的
6. `README` / `CONTRIBUTING`

模板：

| 用途 | 命令 | 来源 |
|---|---|---|
| 安装依赖 | `pnpm install` | `package.json` / `pnpm-lock.yaml` |
| 构建 | `pnpm build` | `package.json#scripts.build` |
| 测试 | `pnpm test` | `package.json#scripts.test` |
| 单测某文件 | `pnpm vitest run src/foo.test.ts` | `package.json` + `vitest.config.ts` |
| Lint/类型 | `pnpm lint && pnpm tsc --noEmit` | `package.json#scripts` |
| 运行 | `pnpm dev` | `package.json#scripts.dev` |

**没有可跑的验证怎么办**：先造一个最小的。三种廉价选择：
- 写一个单文件测试（覆盖你要改的那个函数）。
- 写一个 smoke 脚本：跑起来 → 断言关键输出/退出码 → 打印 PASS/FAIL。
- 如果是纯文档/配置类交付，用"可机械检查的断言"替代（字段是否存在、链接是否可达、schema 校验）。

**反例**：改完直接说"应该没问题"；或引用一个 README 里早就废弃的命令。

## 2. Graph Engineering — 任务 DAG

文本表示就够，别画图：

```
A [读取现状] ──► B [改数据层] ──► C [改接口] ──► E [端到端验证]
                      └──► D [补测试] ──► E
可并行：B 与 A2（环境准备）
```

规则：
- 节点必须是**可独立验证的交付物**（"改一下"不是节点，"登录接口支持 refresh token 且测试通过"才是）。
- 边表示依赖；只有前置验收通过才解锁后继。
- 标出并行点：能并行就并行（对人和 agent 都省时间）。
- 执行中图会变：某节点被证明不可行 → 改图（拆节点/换路径），不要硬推。

**反例**：不画图直接开写；写到一半发现顺序错了推倒重来。

## 3. Prompt Engineering — 3 行规格

每个节点动手前写：

```
目标：<一句话，可验证的终态>
约束：<明确禁止做什么 + 必须遵守什么>
验收：<可判定的检查，1–3 条>
```

示例：

```
目标：/api/orders 支持按 status 过滤，非法 status 返回 400
约束：不改数据库 schema；不加新依赖；保持现有分页参数不变
验收：1) 新增 3 个测试通过 2) 非法值返回 400 且 body 含 error.code
```

**验收断言的写法**：把"好"翻译成"能观察到的事实"。
- 差："优化查询性能" → 好："EXPLAIN 不再出现 Seq Scan，p95 从 800ms 降到 100ms 内"
- 差："代码更清晰" → 好："复杂度函数 ≤10 行，且原有测试全绿"

**反例**：用形容词当验收；验收条件依赖主观判断。

## 4. Context Engineering — 工作记忆

≤15 行，每轮覆盖更新（不是追加），放在你的回复开头或结尾都可以：

```
工作记忆
目标：给导出功能加 CSV 格式
已定：用现有 exporter 抽象；不引新依赖；放 /exports 路由下
事实：exporter 在 src/export/index.ts:12；路由在 src/routes/exports.ts:8
待定：大文件是否要流式（默认：先不流式，>10MB 再说）
下一步：写 format=csv 分支 + 测试
```

配套规则：
- **先检索后精读**：`grep`/`glob` 定位，再定点读；不整目录通读。
- **不重读**：已读文件记下结论，不重复读（除非内容已变）。
- **引用带位置**：`src/foo.ts:42`，不凭记忆复述代码。
- **压缩历史**：长日志/长输出只留结论和关键行。

**反例**：把整个仓库读一遍；把 500 行日志粘进上下文；凭印象说"应该是这样"。

## 5. Loop Engineering — 循环日志与预算

```
节点 B：改数据层
预算：≤10 次工具调用，≤2 次失败重试
尝试1：改 migration → 测试红（字段类型不匹配）
尝试2：改 nullable + 回填 → 测试绿 ✅（工具调用 6 次）
结论：B done
```

失败升级策略（避免原地打转）：

| 情况 | 动作 |
|---|---|
| 第 1 次失败 | 读错误、定位、改一处 |
| 第 2 次失败 | 换假设：是不是定位错了？先加日志/最小复现 |
| 第 3 次仍失败 | 停手：报卡点 + 已试过什么 + 两个备选 + 推荐 |

**停止条件**：DAG 全绿 + 验收全过 → 立刻收尾。不再"再检查一遍"，不追加非必要验证。

**反例**：同一个报错改 5 次；无限扩大验证范围；做完后继续"顺手优化"。
