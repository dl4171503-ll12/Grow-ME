# 共创指南（Contributing）

欢迎一起把 grow-me 打磨得更好用。它是纯 Markdown 规则 + 两个零依赖脚本，改起来门槛很低。

## 先读什么

1. [`grow-me/SKILL.md`](grow-me/SKILL.md) —— 八条规则（改动主要在 `grow-me/` 下）
2. [`RELEASE.md`](RELEASE.md) —— 发布流程（维护者用）
3. [`grow-me/references/sources.md`](grow-me/references/sources.md) —— 设计取舍与版本记录

## 提 Issue

请描述**现象**而不是抽象需求，例如：

- ✅「agent 在 grep 之后又把整个文件读一遍，token 翻倍」+ 复现步骤
- ❌「希望上下文管理更好」

带上：客户端（Codex / Cursor / DSH…）、模型、触发方式、期望行为、实际行为、日志或截图。

## 提 PR

1. Fork → 新建分支：`feat/<一句话>`、`fix/<一句话>`、`docs/<一句话>`
2. 改动尽量小：一个 PR 只解决一个现象/一条规则
3. 必跑本地校验：

```powershell
node grow-me/scripts/validate-skill.mjs grow-me
```

4. 提交信息用一句话说清「改了什么 + 为什么」，例如：
   `fix(context): 明确单次读文件上限为 200 行`
5. PR 描述里写：**解决了什么现象 → 对应哪条规则 → 怎么验证的（命令/结果）**

CI 会自动跑 `validate-skill.mjs` 和 evals 结构检查，红灯不合并。

## 改规则的约定

- 八条规则的**语义**与「反偷懒 / 反空转」红线属于契约，改动前先开 Issue 讨论。
- 新增规则要同步更新：`SKILL.md`（正文 + 参考文件）、`references/`、`CHANGELOG.md`、版本号三处一致。
- 描述（`description`）会直接影响触发率，改动请附 3 条触发用例与 2 条不该触发的反例。

## 版本号

- 维护者统一 bump：`V主.次.修`；规则/行为变更升次版本，纯文档修正升修订号。
- 发布流程固定：**先推本仓库，再更新本机安装副本**（见 RELEASE.md）。

## 协作方式

- 大改动先在 Issue 里对齐设计，再动手。
- 多个 agent 并行协作时可直接用规则八的总线（`grow-me/scripts/bus.mjs`），交接必须带 ack。
- 讨论用中文或英文都可以，技术名词保留原文。
