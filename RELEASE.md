# 发布流程（Release）

> **第一原则：发布新版本的第一件事，是先更新本仓库（GitHub），然后才更新本机安装副本。**
> 仓库是唯一真源：任何人 `git clone` 就能拿到和发布一致的版本。

## 发布清单（按顺序做）

### 1. 先推仓库（第一步，不可跳过）

- [ ] 改版本号（三处必须一致）：
  - `VERSION` → 例如 `V1.4.1`
  - `grow-me/SKILL.md` frontmatter `metadata.version`
  - `grow-me/evals/evals.json` 的 `version`
- [ ] 更新 `CHANGELOG.md`（新增版本小节，写清「改了什么 + 为什么」）
- [ ] 跑校验：`node grow-me/scripts/validate-skill.mjs grow-me`（必须 PASS）
- [ ] 提交：`git add -A && git commit -m "release V1.4.1"`
- [ ] 打 tag：`git tag -a v1.4.1 -m "Grow Me V1.4.1"`
- [ ] **推送：`git push origin HEAD --follow-tags`** ← 完成这一步，仓库才算发布
- [ ] 在 GitHub 上确认：`main` 有该提交、tag 存在、CI 绿灯
- [ ] （可选）创建 Release，附 `.skill` 包：`powershell -File scripts/package.ps1`

### 2. 再更新本机安装副本（第二步）

```powershell
# 注意：仓库已推送之后，才做这一步
Copy-Item 'D:\Grow-ME\grow-me\*' "$env:USERPROFILE\.agents\skills\grow-me\" -Recurse -Force
node "$env:USERPROFILE\.agents\skills\grow-me\scripts\validate-skill.mjs" "$env:USERPROFILE\.agents\skills\grow-me"
```

### 3. 最后同步分发包（可选）

- 桌面/网盘的 `.skill` 包、旧版本副本，统一替换为最新版。
- 如有多个机器安装了技能，按同样方式同步并跑一次校验。

## 一条命令完成第 1 步

```powershell
powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version V1.4.1 -Message "release V1.4.1: <一句话变更>"
```

脚本会：校验三处版本一致 → 跑 `validate-skill.mjs` → 提交 → 打 tag → 推送 → 打印第 2 步命令。

## 版本号规则

| 变更类型 | 版本位 | 例子 |
|---|---|---|
| 规则语义 / 新增规则 / 破坏兼容 | 次版本 | V1.3.0 → V1.4.0 |
| 修正措辞、补例子、修链接 | 修订号 | V1.4.0 → V1.4.1 |
| 仓库结构 / 发布流程 | 次版本 | 同 V1.4.0 |

## 回滚

```powershell
git revert <bad-commit>            # 保留历史
git push origin HEAD
# 或回到旧 tag 重新发一个修订版（推荐，不要 force push 已发布 tag）
```
