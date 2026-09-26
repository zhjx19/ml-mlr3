# ml-mlr3 · mlr3verse 机器学习建模 Skill

> *「模型代码谁都会写，难的是全程不偷偷摸一下测试集。」*

[![version](https://img.shields.io/github/v/tag/zhjx19/ml-mlr3?label=version)](CHANGELOG.md)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-ml--mlr3-blueviolet)](SKILL.md)
[![gates](https://github.com/zhjx19/ml-mlr3/actions/workflows/gates.yml/badge.svg)](https://github.com/zhjx19/ml-mlr3/actions/workflows/gates.yml)
[![Live Verify](https://img.shields.io/badge/verify_examples.R-20%2F20%20PASS-brightgreen)](#验证与测试)
[![Hallucination audit](https://img.shields.io/badge/documented_examples-168%20keys%2C%200%20hallucinated-brightgreen)](examples/EXAMPLE.md)
[![Evals](https://img.shields.io/badge/evals-6%20prompts%20%2B%20assertions-orange)](#验证与测试)
[![GitHub](https://img.shields.io/badge/GitHub-zhjx19%2Fml--mlr3-black)](https://github.com/zhjx19/ml-mlr3)
[![skills.sh](https://skills.sh/b/zhjx19/ml-mlr3)](https://skills.sh/zhjx19/ml-mlr3)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**它把「随手就能写错的 mlr3 建模代码」变成「数据划分、防泄露、调参、最终评估全程守规矩的可复现流程」。**

**30 秒看证据**：两个建模 prompt，各写一遍"无 skill 的典型答案"和"按本 skill 的答案"，再用两把尺子量。典型答案一侧：**6 项纪律违规全 FAIL**（常见种子 `set.seed(42)`、开发期就把测试集切出来直评、把随机 CV 当时序重抽样）+ **8 个字典里根本不存在的键**（`po("imputehci")`、`rsmp("cs")`、`tsk("classif", formula=)`、`msr("classif.kappa")` 等，照抄必报错）。按 skill 写的一侧：**9/9 断言 PASS，0 幻觉键**。对照原文、逐条输出与重跑命令见 **[examples/EXAMPLE.md](examples/EXAMPLE.md)**。

[它解决什么问题](#它解决什么问题) · [它会交付什么](#它会交付什么) · [快速开始](#快速开始) · [触发方式](#触发方式) · [安全边界](#安全边界) · [验证与测试](#验证与测试) · [版本与更新历史](#版本与更新历史)

---

## 它解决什么问题

你让 Agent 写一段 mlr3 建模代码，它多半能跑。但仔细看：测试集早就被 `predict()` 过了；标准化和 SMOTE 在建模前手动做在了全量数据上；调完参顺手用同一个 CV 结果汇报"泛化性能"；并行没量过机器就 `workers` 拉满，把你的核心和内存一起吃掉。

这些错误单看每一行都"没错"，合起来整套性能估计全是虚高的。mlr3 的 R6 引用语义（`$select()` 原地改对象）和图学习器语法（`%>>%` 与 `|>` 混用）又让 LLM 特别容易踩。

本 skill 不是 API 手册——它把这套纪律编码成 Agent 必须执行的硬规则：五大绝对红线 + 默认工作流 + 按需加载的 references。Agent 装上它，写出来的建模流程默认就是规范的。

## 它会交付什么

- 一套从 `partition()` 划分 → PipeOp 特征工程 → `benchmark()` 比较算法 → `auto_tuner()` 调参 → 嵌套重抽样无偏评估 → 授权后一次性测试集评估的**完整可运行 R 代码**
- 分类/回归两个**最小骨架**（已实测），复杂需求自动路由到 10 个 references 文件
- 主动拦截违规请求：测试集直评、图外预处理、没量资源就开满并行

## 快速开始

**前置条件**：R（建议 ≥ 4.2）+ `mlr3verse`；跑 evals 评分器需 Node ≥ 18（可选）。零 API key，全部本地运行。

入口只留两条：**skills.sh**（一条命令）与 **GitHub**（clone 后软链，适配任意 Agent 的 skills 目录）。

方式一：skills.sh

```bash
npx skills add zhjx19/ml-mlr3
```

方式二：GitHub（ZCode / Claude Code / OpenCode 等只要读 skills 目录的都适用）

```bash
git clone https://github.com/zhjx19/ml-mlr3.git
ln -s "$(pwd)/ml-mlr3" <你的-agent-skills-目录>/ml-mlr3
```

装完对 Agent 说：

```text
用 mlr3verse 给这份数据建一个分类模型流程：先划分数据，比较几个算法，最后评估。
```

## 触发方式

- 「用 mlr3 / mlr3verse 帮我建个预测模型」
- 「比较几个算法哪个好，用 mlr3」
- 「mlr3 怎么调超参数 / auto_tuner 怎么写」
- 「SMOTE 放在哪里才不会泄露」
- 「嵌套重抽样怎么做」
- 「GraphLearner / PipeOp / 图学习器怎么搭」
- 「特征选择和调参一起做」

## 安全边界

| 红线 | 行为 |
|---|---|
| 测试集绝对隔离 | 开发期禁止对 `split$test` 做预测/汇总/可视化/调参；最终评估**必须先询问用户**，获许可后只评估一次 |
| R6 引用语义 | 修改 Task/Learner 前必须 `$clone(deep = TRUE)`，不污染原对象 |
| 防数据泄露 | 一切预处理（插补/编码/标准化/PCA/SMOTE/特征选择）封装进 PipeOp 图，在重抽样内部拟合 |
| 并行先量资源 | 自动开并行，但 `future::plan()` 前必须探测 `availableCores()` + `ps_system_memory()`，按真实负载定 workers；外层按折并行时 `set_threads(learner, n = 1L)` |
| 嵌套重抽样用途 | 只做无偏比较；真正调参走 `auto_tuner$train()` |

不会做：深度学习、非表格数据、tidymodels 工作流（指引用户改用对应生态技能）、轻量探索性分组建模（一个 dplyr `nest` + `map` 就够，不必上 mlr3）。

## 它和 tidymodels skill 有什么不同

二者服务同一建模目标，对象模型不同，**不要混用语法**：

| 维度 | tidymodels skill | 本 skill |
|---|---|---|
| 预处理 | `recipe()` + `workflow()` | R6 `Task` + PipeOp 图 + `ppl("robustify")` |
| 调参 | `tune_grid()` 等 tune 系 | `auto_tuner()` / `to_tune()`，分支路由调参 |
| 特征选择 | recipes + finetune | `auto_fselector()` / `po("filter")` 联合调优 |
| 用户指名 mlr3verse | 转介到本 skill | 直接按本 skill 流程执行 |

## 文件结构

```text
ml-mlr3/
├── SKILL.md                   # 入口：API 现场校验、铁律、五大红线、默认工作流、最小骨架
├── evals.json                 # 6 个评测 prompt + 机器可查断言（对标 tidymodels 官方 evals 形态）
├── references/
│   ├── data-spending.md       # 数据划分与测试集隔离（含最终评估话术）
│   ├── resampling.md          # CV/重复CV/holdout/分组/时序custom滚动折
│   ├── feature-engineering.md + feature-engineering/  # PipeOp 预处理总览与 4 个细分
│   ├── tuning.md              # auto_tuner / auto_fselector
│   ├── evaluation.md          # 指标、ROC/PRC/残差图、benchmark、最终评估
│   └── advanced-workflows.md  # 5 大进阶工作流（调优benchmark/图调参/不平衡/联合调优/早停）
├── scripts/
│   ├── verify_examples.R      # 骨架回归：20 个案例一键实跑（含字典探针，防文档写回已移除的 API）
│   ├── list_example_deps.R    # 从示例本身算出要装哪些 R 包（CI 依赖清单不再手抄）
│   ├── check_answer_api.R     # 幻觉键体检：抓回答里字典中不存在的 lrn()/po()/msr()/rsmp()/tnr()/tsk()/ppl()
│   └── run_evals.mjs          # evals 断言评分器（零依赖 Node）
├── examples/
│   ├── EXAMPLE.md             # 证据件：无/有 skill 双向回放 + 两把尺子的原始输出 + 重跑命令
│   └── replay/                # 四份真实对照答案（baseline-* / skilled-*），可被上面两个评分器直接吃
├── evals/outputs/             # 评测回答存放处（eval-<id>.md）
└── .github/workflows/
    └── gates.yml              # CI：全量 20 例（ubuntu + windows）+ 全库幻觉键体检 + 断言引擎自检
```

## 验证与测试

**骨架回归**（改动 SKILL.md 示例后必跑）：

```bash
Rscript scripts/verify_examples.R
```

最近一次实跑输出：

```text
[PASS] 最小骨架·分类
[PASS] 最小骨架·回归
[PASS] auto_tuner（svm 条件参数）
[PASS] ppl(branch) 分支调参
[PASS] 时序·custom 滚动折
[PASS] benchmark 调优后比较
[PASS] 早停·best_valid_score
[PASS] selector·整数列与符号选择器
[PASS] greplicate + materialize
[PASS] datefeatures 日历展开
[PASS] Task·访问器语义
[PASS] 调参档案·dtype 与 trafo 尺度
[PASS] learner$deadline
[PASS] 字典探针·文档点名对象
[PASS] PipeOp 类型前置·splines/boxcox/subsample/select
[PASS] selector·integer 与 affected_cols 语义
[PASS] 文档签名·图调参与 lts 预置空间
[PASS] 重抽样实测坑·bootstrap/封装兜底/分层/线程
[PASS] 文档口径·spatialsign 归属 / 依赖包 / validate='test' 静默
[PASS] 文档口径·robustify 图访问器 / 参数 id / 覆盖默认值

=== 汇总：20/20 PASS ===
```

**CI 门禁 ≠ 免跑凭证。** 它跑的四道与本机同源，依赖清单也不手抄——由 `scripts/list_example_deps.R` 从示例本身算出（"扫字典算清单"会漏掉字典提供方自己，`classif.lightgbm` 的注册包就是活例子；细则见 CHANGELOG）：

```bash
Rscript scripts/list_example_deps.R                       # 示例到底要哪些包、本机缺哪个
Rscript scripts/list_example_deps.R --print-list          # 只打印待装包名（空格分隔）
Rscript scripts/list_example_deps.R --install             # CI 用的就是这一条
Rscript scripts/list_example_deps.R --mirror --repos <你的 CRAN 镜像>   # 预飞：CI 那份仓库快照里有没有它
```

`.github/workflows/gates.yml` 每次 push / PR 做三件事：按上面的清单装依赖 → **全量**跑 20 例（ubuntu + windows，不砍案例、不砍折数、不砍预算）→ 给全部文档示例做一次幻觉键体检；另一个 job 跑断言引擎自检。**红灯自带病因**：失败时把 `FAIL:` / `[幻觉]` 行、以及安装环节的逐包加载回执写成 workflow annotation，而不是只留一个状态灯。**环境与包安装：门禁只诊断、不替你修**——缺什么（含系统库）就点名什么，你自己装好再重试；仓库不会替你 `apt-get`，也不会为了让灯变绿而放宽断言或砍清单。当前一处已知限制：ubuntu job 红在镜像缺 `libglpk.so.40`（igraph 的 RSPM 二进制需要它），不影响任何示例与正文口径，windows job 与本机全绿。

诊断脚本自己也有回归：`Rscript scripts/test_install_logged.R scripts/list_example_deps.R`（十节断言）；`--install-probe <包>` 能在本机临时库里复演干净机器的安装路径，绝不动用户库。

**改完示例代码仍须本机实跑一遍**，并把通过率写进 CHANGELOG——CI 只证明"这两个平台、这个时点的 CRAN 快照"跑得通，你交付给用户的环境是你自己的机器，两份实测记录不能互相顶替。

**评测**（evals.json 的 6 个 prompt 覆盖标准流程/红线拦截/时间序列/不平衡/回归/嵌套重抽样陷阱）：把回答存进 `evals/outputs/eval-<id>.md`，然后：

```bash
node scripts/run_evals.mjs --selftest   # 引擎自检（黄金 0 FAIL、违规 5/5、未闭合 fence 5/5）
node scripts/run_evals.mjs              # 逐断言评分，任一 FAIL 退出码 1
```

2026-09-26 双向回放结果（开发者自测）：

- **A 组**（按本 skill 纪律作答 ×6）：26 断言全 PASS——skill 教的写法全部通过红线审计
- **B 组**（模拟无 skill 的典型错误 ×6，见 `evals/outputs/negative/`）：12 FAIL 全部抓获——常见种子、测试集直评、图外 SMOTE、时序随机 CV、没量资源就开满并行、嵌套重抽样概念混淆一个都跑不掉

**幻觉键体检**（断言引擎的补尺）。断言只查纪律，查不出"代码写得像模像样但 `po("imputehci")` 这个键压根不存在"：

```bash
Rscript scripts/check_answer_api.R examples/replay/skilled-eval-1.md examples/replay/baseline-eval-1.md
```

它把回答里所有 `lrn()/po()/msr()/rsmp()/tnr()/tsk()/ppl()` 的首参逐个对着 mlr3verse 字典探测，键不存在就点名并附字典自己的 "Did you mean" 提示，退出码 1。本机实测：`baseline-*` 两份 4+4 个幻觉键全部被抓；把 `SKILL.md` + 全部 `references/` + A 组 6 份 + `examples/replay/skilled-*` 一起喂进去，**168 个唯一键 0 幻觉**（这个数随正文增删而变，以现跑为准）。CI 每次 push 都做这同一次体检——skill 教的代码哪天因为上游改名而失效，门禁会先红，而不是等用户投诉。

## 版本与更新历史

**当前发布版本：v2.4.0**（CHANGELOG 与 `SKILL.md` frontmatter 同步为 2.4.0；线上最新 tag 仍是 `v2.3.0`，`v2.4.0` 的 tag 等一次明确授权再打）。本仓库自己的版本号与更新历史是产品的一部分，跟着仓库走：

| 在哪看 | 内容 |
|---|---|
| [`CHANGELOG.md`](CHANGELOG.md) | 逐版记录，**每版讲清"为什么改"**，不只是改动清单；未发布的改动堆在 `[Unreleased]` 段 |
| [tags](https://github.com/zhjx19/ml-mlr3/tags) | 打 tag 即发版：`v2.3.0` ← `v2.2.0` ← `v2.1.0`；首屏 `version` 徽章读的是最新 tag，所以它此刻仍显示 `v2.3.0` |
| `SKILL.md` frontmatter 的 `version:` | 给 runtime / 市场读的那一份 |

**三处必须逐字相同，且这件事有机检**：`scripts/verify_examples.R` 开头有一条不计入用例数的自检，比对 SKILL.md frontmatter / README 本节 / CHANGELOG 最新已发布条目，不一致就直接红。为什么值得钉一道尺：这个仓库真有过两份平行的版本元数据（一份 marketplace 声明和 SKILL.md 各说各话），那份已归档移除，但"版本号抄在两个地方就会分家"是结构性风险，不是巧合。

发版纪律：`[Unreleased]` 攒到的改动要经用户明确授权才打 tag；打 tag 前四道门禁须全绿，且示例代码改动必须有**本机实跑**记录（不只是 CI 绿）。至于 skill 教的 mlr3 用法本身，正文刻意**不写上游包的版本号与迁移账目**——那是 mlr3 自己 NEWS 的职责，本 skill 只保留一行实测环境记录（见 SKILL.md「API 现场校验」）与当场探测的纪律。

## 致谢

- [tidymodels/skills](https://github.com/tidymodels/skills) —— 官方 skill 的 evals/断言形态与「纪律优先」方法论是本 skill 的对标来源
- [mlr3book](https://mlr3book.mlr-org.com) 与 [mlr3gallery](https://mlr3gallery.mlr-org.com) —— mlr3verse 生态权威文档
- [krishi-shah/ml-engineer-skills](https://github.com/krishi-shah/ml-engineer-skills) —— 「ML 错误检查器」思路的启发
- 上游 mlr3 / mlr3pipelines / mlr3tuning / mlr3fselect 各包 NEWS 是新用法的线索来源；技能正文只保留**实测通过**的当前写法，不留版本号账目

## License

[Apache License 2.0](LICENSE)

---

*mlr3 生态迭代快，照抄示例前先按 SKILL.md「API 现场校验」节探测对象是否存在；`scripts/verify_examples.R` 里的字典探针会把不存在的键直接判 FAIL。*
