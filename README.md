# ml-mlr3 · mlr3verse 机器学习建模 Skill

> *「模型代码谁都会写，难的是全程不偷偷摸一下测试集。」*

[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-ml--mlr3-blueviolet)](SKILL.md)
[![Live Verify](https://img.shields.io/badge/verify_examples.R-14%2F14%20PASS-brightgreen)](#验证与测试)
[![Evals](https://img.shields.io/badge/evals-6%20prompts%20%2B%20assertions-orange)](#验证与测试)
[![GitHub](https://img.shields.io/badge/GitHub-zhjx19%2Fml--mlr3-black)](https://github.com/zhjx19/ml-mlr3)
[![skills.sh](https://skills.sh/b/zhjx19/ml-mlr3)](https://skills.sh/zhjx19/ml-mlr3)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**它把「随手就能写错的 mlr3 建模代码」变成「数据花费、防泄露、调参、最终评估全程守规矩的可复现流程」。**

[它解决什么问题](#它解决什么问题) · [它会交付什么](#它会交付什么) · [快速开始](#快速开始) · [触发方式](#触发方式) · [安全边界](#安全边界) · [验证与测试](#验证与测试)

---

## 它解决什么问题

你让 Agent 写一段 mlr3 建模代码，它多半能跑。但仔细看：测试集早就被 `predict()` 过了；标准化和 SMOTE 在建模前手动做在了全量数据上；调完参顺手用同一个 CV 结果汇报"泛化性能"；并行悄悄吃满你全部核心。

这些错误单看每一行都"没错"，合起来整套性能估计全是虚高的。mlr3 的 R6 引用语义（`$select()` 原地改对象）和图学习器语法（`%>>%` 与 `|>` 混用）又让 LLM 特别容易踩。

本 skill 不是 API 手册——它把这套纪律编码成 Agent 必须执行的硬规则：五大绝对红线 + 默认工作流 + 按需加载的 references。Agent 装上它，写出来的建模流程默认就是规范的。

## 它会交付什么

- 一套从 `partition()` 划分 → PipeOp 特征工程 → `benchmark()` 比较算法 → `auto_tuner()` 调参 → 嵌套重抽样无偏评估 → 授权后一次性测试集评估的**完整可运行 R 代码**
- 分类/回归两个**最小骨架**（已实测），复杂需求自动路由到 10 个 references 文件
- 主动拦截违规请求：测试集直评、图外预处理、自动开并行

## 快速开始

**前置条件**：R（建议 ≥ 4.2）+ `mlr3verse`；跑 evals 评分器需 Node ≥ 18（可选）。零 API key，全部本地运行。

方式一：skills.sh

```bash
npx skills add zhjx19/ml-mlr3
```

方式二：Claude Code plugin marketplace

```text
/plugin marketplace add zhjx19/ml-mlr3
/plugin install ml-mlr3@ml-mlr3
```

方式三：手动链接进任意 Agent 的 skills 目录（ZCode / Claude Code / OpenCode 均适用）

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
| 并行需授权 | `future::plan()` 前先报核心数并询问，Windows 用 `multisession` |
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
│   ├── verify_examples.R      # 骨架回归：14 个案例一键实跑（含字典探针，防文档写回已移除的 API）
│   └── run_evals.mjs          # evals 断言评分器（零依赖 Node）
└── evals/outputs/             # 评测回答存放处（eval-<id>.md）
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

=== 汇总：14/14 PASS ===
```

**评测**（evals.json 的 6 个 prompt 覆盖标准流程/红线拦截/时间序列/不平衡/回归/嵌套重抽样陷阱）：把回答存进 `evals/outputs/eval-<id>.md`，然后：

```bash
node scripts/run_evals.mjs --selftest   # 引擎自检（黄金 0 FAIL、违规 5/5、未闭合 fence 5/5）
node scripts/run_evals.mjs              # 逐断言评分，任一 FAIL 退出码 1
```

2026-09-13 双向回放结果（开发者自测）：

- **A 组**（按本 skill 纪律作答 ×6）：26 断言全 PASS——skill 教的写法全部通过红线审计
- **B 组**（模拟无 skill 的典型错误 ×6，见 `evals/outputs/negative/`）：12 FAIL 全部抓获——常见种子、测试集直评、图外 SMOTE、时序随机 CV、未询问开并行、嵌套重抽样概念混淆一个都跑不掉

## 致谢

- [tidymodels/skills](https://github.com/tidymodels/skills) —— 官方 skill 的 evals/断言形态与「纪律优先」方法论是本 skill 的对标来源
- [mlr3book](https://mlr3book.mlr-org.com) 与 [mlr3gallery](https://mlr3gallery.mlr-org.com) —— mlr3verse 生态权威文档
- [krishi-shah/ml-engineer-skills](https://github.com/krishi-shah/ml-engineer-skills) —— 「ML 错误检查器」思路的启发
- 上游 mlr3 / mlr3pipelines / mlr3tuning / mlr3fselect 各包 NEWS 是新用法的线索来源；技能正文只保留**实测通过**的当前写法，不留版本号账目

## License

[Apache License 2.0](LICENSE)

---

*mlr3 生态迭代快，照抄示例前先按 SKILL.md「API 现场校验」节探测对象是否存在；`scripts/verify_examples.R` 里的字典探针会把不存在的键直接判 FAIL。*
