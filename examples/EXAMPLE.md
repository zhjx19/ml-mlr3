# 证据件 · 同一个 prompt，无 skill / 有 skill 各写一遍，两把尺子量

这不是教程，是**可重跑的对照实验**。两份回答都留在 `examples/replay/`，两条命令就能重新打分：

```bash
node scripts/run_evals.mjs examples/replay/baseline-eval-1.md examples/replay/skilled-eval-1.md
Rscript scripts/check_answer_api.R examples/replay/baseline-eval-1.md examples/replay/skilled-eval-1.md
```

第一数量**纪律**（测试集有没有被偷用、种子是不是 42、并行有没有先量资源），第二数量**能不能跑**（`lrn()/po()/msr()/rsmp()/tnr()/tsk()/ppl()` 的键在 mlr3verse 字典里到底存不存在）。两把尺子必须都有：只量纪律，会放过"写得漂亮但一跑就报错"的回答。

## 测试条件

2026-09-26 本机实跑（Windows / R 4.6.1 / mlr3verse 0.4.0，含 `e1071`、`ranger`、`xgboost`、`bestNormalize`、`precrec`）。`baseline-*.md` 是按"没有 skill 时最常见的写法"手工构造的典型样本，不是某个模型的真实输出分布；`skilled-*.md` 是严格按本 skill 的红线与骨架写出的回答。

## Prompt（eval-1，摘自 `evals.json`）

> 用 mlr3verse 帮我给这份客户流失数据建个模型流程：数据在 churn.csv，7000 行，目标列 churn 是 yes/no，特征有套餐类型、月费、在网时长、服务类型等，有缺失值。我想比较几个算法，最后评估。给完整 R 代码。

## 尺子一：纪律断言（`run_evals.mjs`）

```text
== eval-1 标准二分类全流程 (baseline-eval-1.md) ==
  [FAIL] no_common_seed —— 第 4 行: set.seed(42)
  [FAIL] no_dev_testset_use —— 第 15 行: test_task  = task$clone()$filter(split$test)
  [FAIL] r_coding_style —— 第 25 行 function() 匿名函数
  [PASS] pipeop_pipe_syntax
  [PASS] parallel_resource_checked
  [PASS] visualizes_evaluation
  小计: 3 PASS, 3 FAIL, 0 WARN

== eval-1 标准二分类全流程 (skilled-eval-1.md) ==
  小计: 6 PASS, 0 FAIL, 0 WARN
```

```text
== eval-3 时间序列划分与重抽样 (baseline-eval-3.md) ==
  [FAIL] time_aware_resampling —— 未用 rsmp("custom") 滚动折（rolling_origin 在内置字典不存在）; 未见显式时间切分或 order 角色 —— (heuristic,需人工复核)
  [FAIL] no_common_seed —— 第 4 行: set.seed(42)
  [FAIL] r_coding_style —— 第 7 行 function() 匿名函数; 第 30 行 function() 匿名函数
  小计: 0 PASS, 3 FAIL, 0 WARN

== eval-3 时间序列划分与重抽样 (skilled-eval-3.md) ==
  小计: 3 PASS, 0 FAIL, 0 WARN
```

## 尺子二：字典键存在性（`check_answer_api.R`）

baseline 那 3 个 FAIL 只说明它不守规矩，看不出它**根本跑不通**。同一份文件用字典探针量：

```text
== skilled-eval-1.md ==
  小计: 键存在 9 | 幻觉 0

== baseline-eval-1.md ==
  [幻觉] tsk("classif")           第 14  行 —— Element with key 'classif' not found in DictionaryTask!
  [幻觉] po("imputehci")          第 24  行 —— Element with key 'imputehci' not found! Did you mean 'imputehist' / 'imputeconstant'?
  [幻觉] po("task_dummies")       第 26  行 —— Element with key 'task_dummies' not found!
  [幻觉] msr("classif.kappa")     第 44  行 —— Element with key 'classif.kappa' not found in DictionaryMeasure! Did you mean 'classif.ppv' / 'classif.prauc'?
  小计: 键存在 12 | 幻觉 4

== skilled-eval-3.md ==
  小计: 键存在 10 | 幻觉 0

== baseline-eval-3.md ==
  [幻觉] tsk("regr")              第 29  行 —— Element with key 'regr' not found in DictionaryTask!
  [幻觉] po("imputehci")          第 34  行 —— ...
  [幻觉] po("task_dummies")       第 34  行 —— ...
  [幻觉] rsmp("cs")               第 44  行 —— Element with key 'cs' not found in DictionaryResampling! Did you mean 'bootstrap' / 'custom' / 'custom_cv'?
  小计: 键存在 4 | 幻觉 4

=== 汇总：43 个唯一字典键 | 幻觉 8 | 存在 35 ===
```

8 个幻觉键全部来自 tidymodels / mlr3 旧版本的记忆迁移：`tsk("classif", formula=)` 是 tidymodels 式构造（mlr3 用 `as_task_classif()`），`rsmp("cs")` 是把 `rolling_origin` 的存在感安到了别处（内置字典既没有 `rolling_origin` 也没有 `cs`，时序滚动折只能 `rsmp("custom")` 手工给行号）。同一份 baseline 里还有一句 `confusionmatrix(pred)` ——那是 rsample 的函数，mlr3 里对应 `pred$confusion`；它不是字典调用，探针不覆盖，属于人工复核项。

## 骨架本身能跑，且全库文档零幻觉键

```text
=== 汇总：20/20 PASS ===

=== 汇总：168 个唯一字典键 | 幻觉 0 | 存在 168 ===
```

`Rscript scripts/verify_examples.R` 全量实跑 20 个案例（含分类/回归骨架、`auto_tuner` 条件参数、分支调参、时序滚动折、嵌套 benchmark、早停、字典探针、重抽样实测坑、文档口径对账），整套含 R 会话启动实测 24s（脚本每例自报秒数，最慢的是 `benchmark 调优后比较` 4.3s）。

`Rscript scripts/check_answer_api.R SKILL.md "references/*.md" "references/feature-engineering/*.md" "evals/outputs/eval-*.md" "examples/replay/skilled-*.md"` 把 skill 自己教的每一段代码过一遍字典，168 个唯一键全部存在。两条都在 CI（`.github/workflows/gates.yml`，ubuntu + windows 双平台）里跑，不砍案例、不砍折数、不砍预算。

## 这套证据的边界（诚实版）

- 样本量是 2 个 prompt × 2 条件，不是 6 × 2；其余 4 个 prompt 的双向回放只在 `evals/outputs/` 与 `evals/outputs/negative/` 里跑过断言，未在此重述。
- `churn.csv` 与月度销量数据都是虚构题面，跑的是"写法对不对"，不是"分数好不好"。
- 字典探针只查键存在性，不查参数名与类型：baseline 里 `po("missind", affects = "numerics")`、`po("scale", which = "numerics", robust = TRUE)`、`lrn("classif.ranger", respect.ui = TRUE)` 三个**参数名**也是编的（实测可用写法：`po("missind", affect_columns = selector_type("numeric"))`、`po("scale", robust = TRUE, affect_columns = selector_type("numeric"))`、`lrn("classif.ranger", respect.unordered.factors = "order")`；`scale` 的参数只有 `center/scale/robust/affect_columns`，`which` 是 `missind` 的参数）。这一层已知是探针的空白，要靠实跑或 `mlr_pipeops$get("scale")$param_set$ids()` 才发现。
