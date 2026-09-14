# Changelog

本仓库遵循「发版讲清为什么改」的迭代纪律：每个版本记录动机，不只是改动清单。

## [2.1.1] — 2026-09-14 · 协议切换为 Apache-2.0

### Changed
- **LICENSE：MIT → Apache-2.0**。为什么改：与同门技能（auto-geogebra 等）统一许可证；Apache-2.0 含明确的专利授权条款，对下游采用者更友好。变更范围：LICENSE 全文替换、README 徽章与 License 节、SKILL.md 补充 `license` 字段、marketplace 版本 2.1.1。

## [2.1] — 2026-09-13 · evals 真实回放 + 时序事实修正

### Fixed
- **时序重抽样事实修正（本轮最重要）**：为什么改——用户提供的上游 changelog 触发 API 复查，实测发现 `rsmp("rolling_origin")` 在 mlr3 1.7.1 内置字典**不存在**（只有 bootstrap/custom/custom_cv/cv/holdout/insample/loo/repeated_cv/subsampling），且 `order` 角色实测**不会**让随机 CV/holdout 按时间切分（holdout 测试集散布中段）。SKILL.md、resampling.md、data-spending.md 原来教的 rolling_origin 写法运行即报错。改为教：按时间位置显式切分 + `rsmp("custom")` 手写滚动折（实测每折训练窗严格早于验证窗）；`group` 角色自动分组切分实测成立，保留。
- **verify_examples.R 增至 6 案例**：为什么改——rolling_origin 之错能静默存活至今，正是因为 verify 没覆盖时序；新增「时序·custom 滚动折」案例（含每折 train<test 断言）防同类回归。重跑 6/6 PASS。
- **评分器未闭合 fence 漏检**：为什么改——B 组阴性对照暴露代码块缺闭合 ``` 时整块不被审计（seed 42 / split$test 全漏）。已修并固化进 selftest（未闭合样例期望 5/5 命中）。
- **parallel_authorized 断言补挂**：为什么改——红线 5（并行需授权）此前没有挂到任何 eval，属于断言覆盖缺口；已挂 eval-1/eval-5。

### Added
- **版本演进提示（上游 changelog 摘要）**入 SKILL.md 版本锚定节：mlr3 1.8.0 BREAKING（pima→diabetes）+ msr("best_valid_score")、mlr3tuning ≥1.6.1 AutoTuner 深克隆修复、mlr3fselect ≥1.7.0 rfecv 方向 bug 修复（低版本 rfecv+最小化指标结果无效）、mlr3pipelines 0.11 实测可用项（插补支持 Date/POSIXct、po("splines")、$predict_newdata_fast）。
- **evals 双向回放闭环**：A 组（按 skill 纪律作答×6）26 断言全 PASS；B 组阴性对照（模拟无 skill 典型错误×6）12 FAIL 全部抓获。回答样例入库 `evals/outputs/` 与 `evals/outputs/negative/`，任何人可重放。

### 验证
- `Rscript scripts/verify_examples.R` → 6/6 PASS（2026-09-13，含时序案例）
- `node scripts/run_evals.mjs --selftest` → 引擎自检 PASS（黄金/违规/未闭合三样例）
- A 组回放 26 PASS / 0 FAIL；B 组阴性对照 12 FAIL 全抓获

### Pub（公开发布改造，发布至 github.com/zhjx19/ml-mlr3）
- 为什么改：私用转公开，按出生证清单补必备件。新增 LICENSE（MIT）、`.claude-plugin/` marketplace 双通道（结构对齐 tidymodels/skills）、README 致谢节与 License 节、安装三通道（skills.sh / plugin marketplace / 手动链接，移除私人路径）；SKILL.md 负触发中本机技能名引用改为通用表述；「与 Autos 版关系」内部历史节归档至本 CHANGELOG 1.x 条目。
- 发布动作：`master` → `main` 改名后首推，tag `v2.1.0`（对应本节 + [2.0] 内容）。

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
