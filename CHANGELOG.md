# Changelog

本仓库遵循「发版讲清为什么改」的迭代纪律：每个版本记录动机，不只是改动清单。

## [2.0] — 2026-09-13 · 鲁班工坊第二轮打磨

### Added
- **SKILL.md「版本锚定」节**：为什么改——mlr3 生态迭代快（本轮实测 mlr3 1.7.1 / R 4.6.1，`verify_examples.R` 5/5 PASS），无版本锚定时 Agent 遇 API 报错无从判断是代码错还是版本差。
- **`evals.json` 2.0 + `scripts/run_evals.mjs`**：为什么改——旧 `test-prompts.json` 只有 3 个 dry-run 提示语、无机器可查标准，评测全凭手感。对齐 tidymodels 官方 skills 的 evals 形态（prompt + expected_output + assertions），扩到 6 题覆盖标准流程/红线拦截/时间序列/不平衡/回归/嵌套重抽样陷阱；评分器零依赖 Node 可跑，自带 `--selftest` 引擎自检（黄金样例 0 FAIL、违规样例 5 断言全命中）。原 `test-prompts.json` 删除（内容被 evals.json 完全覆盖，git 历史可查）。
- **SKILL.md「评估必附可视化」小节**：为什么改——对标 tidymodels 官方 skill 的评估要求（分类 ROC/校准、回归 obs-vs-pred/残差），此前只藏在 `references/evaluation.md` 里，主线不提 Agent 就常漏交付。

### Fixed
- **precrec 依赖活体暴露**：为什么改——`autoplot(type="roc")` 在本机实跑报错 `packages could not be loaded: precrec`（mlr3viz 画 ROC/PRC 依赖它但 mlr3verse 不自带），已装包复测 PASS 并把 precrec 写进「依赖包提示」与可视化代码块注释。
- **frontmatter 负面触发路由**（上轮遗留改动，本轮固化）：description 增加「不要用于」清单，与 tidy-data / data-cleaning / tidymodels skill 划清边界，防止误路由。

### 验证
- `Rscript scripts/verify_examples.R` → 5/5 PASS（2026-09-13）
- `node scripts/run_evals.mjs --selftest` → 引擎自检 PASS

## [1.x] — 2026-08 及之前

- 初始转换（Autos aardio 版 → Claude Code skill）
- Phase 0.5 基线 + auto-optimize 第一轮：frontmatter 对齐、dim2/红线1 references 一致性声明、dim5 依赖包提示与缩写来源、verify 脚本铁律化（见 git log 36c1312 及之前）
