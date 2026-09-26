---
name: ml-mlr3
description: >-
  Discipline-hardened mlr3verse (R) machine learning for tabular data: build a
  predictive model, benchmark learners, tune hyperparameters, and do in-graph
  feature engineering, while the test set stays untouched until authorized,
  every preprocessing step sits inside the resampling, and parallelism is sized
  from measured cores/memory. Use when the user needs mlr3 / mlr3verse /
  GraphLearner / PipeOp / auto_tuner / auto_fselector / ppl("robustify") work.
  用户需要用 R mlr3verse 框架做表格数据机器学习建模——构建预测模型、比较算法、
  调优超参数、做特征工程或特征选择，或提到上述关键词时使用。
  不要用于：深度学习、非表格数据（图像/文本/NLP）；tidymodels 工作流（改用 tidymodels 生态技能）；
  轻量探索性分组建模（dplyr nest + map 即可）；数据清洗本身。
license: Apache-2.0
---

# mlr3verse 表格数据机器学习建模


## 技能定位与边界

本技能包覆盖 mlr3verse 机器学习建模全流程：数据分割 → PipeOp 特征工程 → 模型选择 → 调优/特征选择 → 嵌套重抽样评估 → 最终拟合。

**不在范围内**：深度学习、非表格数据（图像/文本/NLP）、tidymodels 工作流（改用 tidymodels 生态技能）。

## API 现场校验（不背版本号）

mlr3 生态迭代快，本技能不维护版本对照表：**版本号全文只出现在下面这一行实测记录里**，它回答"这些示例最近何时、在什么环境跑通"，不回答"哪个 API 从哪个版本起存在"。规则只有一条：**照抄任何对象名/参数名之前，先当场探测它是否存在**。示例的可执行契约由 `scripts/verify_examples.R`（20 例实跑）和 `scripts/run_evals.mjs`（静态断言）把守——改完示例代码这两个都必须重跑，跑通后刷新这行记录。

> 实测记录：2026-09-26 · R 4.6.1 / mlr3 1.8.0 / mlr3pipelines 0.12.0 / mlr3tuning 1.7.0 / mlr3fselect 1.7.0 / paradox 1.0.1 · `verify_examples.R` 20/20 PASS

```r
mlr_learners$keys(); mlr_pipeops$keys(); mlr_measures$keys()
mlr_tuners$keys(); mlr_fselectors$keys(); mlr_tasks$keys()
mlr_pipeops$get("datefeatures")$param_set$ids()   # PipeOp 参数名
lrn("classif.xgboost")$param_set$ids()            # 学习器参数名
getNamespaceExports("mlr3verse")                   # 到底哪些函数被再导出（比 exists() 可靠）
```

判断"某个函数能不能裸写"用 `getNamespaceExports("mlr3verse")` 与 `getNamespaceExports("mlr3pipelines")` 的导出集，别用 `exists()`：导出集只回答"这个包到底导出了什么"，而 `exists()` 取决于当前 search path 与脚本跑到一半的状态——实测 `exists("selector_positive")` 在新会话里是 `FALSE`，在跑到后半段的验证脚本里却成了 `TRUE`（具体成因未定位，正是这类不确定性让它不适合当判据）。

三类报错信号按此顺序排查，别急着怀疑自己的逻辑：

1. `could not find function "x"` / `attempt to apply non-function`：对象已被移除，或它现在是**字段**（去掉括号），或**不再由 mlr3verse 再导出**（加 `mlr3pipelines::` 前缀）。
2. `Cannot set argument 'x' ... Did you mean 'y'`：参数改名或变成条件参数，先查 `$param_set$ids()`。
3. 字典键名保留下划线（`grid_search`、`learner_cv`），照 `keys()` 的输出写最稳；`tnr()`/`po()` 的糖才做规范化。

已实测的当前 API 事实（写示例时按这些来，不要引用左侧的旧写法）：

| 现在这样写 | 不要这样写 |
|---|---|
| `set_validate(learner, validate = 0.3)` | learner 构造参数 `validate =` |
| `ppl("greplicate", graph = ..., n = 3L)` | 独立函数 `greplicate()` |
| `tsk("diabetes")` | `tsk("pima")`（已不在字典） |
| `fs("sequential")` / `fs("rfe")` / `fs("rfecv")` | `fs("forward")` / `fs("backward")` / `fs("bonu")`（已不在字典） |
| `task$feature_names` / `task$target_names` / `task$nrow` / `task$row_ids` | `task$cols()` / `task$nrow()` / `task$row_ids()`（会报 attempt to apply non-function） |
| 自己 `cor(task$data(cols = NULL)[, .SD, .SDcols = task$feature_names])` | `task$correlation()`（已移除） |
| `mlr_pipeops$keys()` / `ls(asNamespace("mlr3pipelines"), pattern = "^pipeline_")` | 裸写 `po()` / `ppl()` 当字典浏览器（报 `cannot coerce type 'environment' to vector...`） |
| `po("splines", df = 5, affect_columns = selector_type(c("numeric", "integer")))` | `po("splines", df = 5)` 直接进图（默认作用全部列，遇 factor 崩在内部 `quantile()` 上，报 `non-numeric argument to binary operator`） |
| `po("subsample", frac = .5, stratify = TRUE, use_groups = FALSE)` | `po("subsample", stratify = TRUE)`（报 `Cannot combine stratification with grouping`） |
| `mlr3pipelines::selector_positive()`（等 6 个符号类） | 裸写 `selector_positive()` / `neg()`（`mlr3verse` 不再导出这 6 个，且 `neg` 压根不存在） |
| `lts("classif.ranger.default")$get_learner()` | `search_space = lts(...)`（`lts()` 返回 TuningSpace R6，`$learner` 只是 id 字符串） |
| `learner$encapsulate("evaluate", default_fallback(learner))` | `learner$encapsulate = c(train = , predict = )` / `learner$fallback = ...`（两者运行即报错，详见「错误处理与日志」） |
| `task$set_col_roles("y", roles = c("target", "stratum"))` 后再 `rsmp("cv")` | `rsmp("cv", stratify = TRUE)`（重抽样类没有 `stratify`，报错原文点名该参数） |

两条实测确认的纪律：`AutoTuner` / `AutoFselector` 的 `$clone(deep = TRUE)` 得到的是**全新未训练**对象（`$model`、`$archive` 为空），可以放心各自训练互不干扰——但 `Task` 的 `$select()` / `$filter()` 和 `$param_set$values` 仍是原地修改（见红线 2）。`fs("rfecv")` 配最小化指标（`classif.ce` 等）时，必须自己核对 `selection_result` 里特征数与性能的走向是否单调，别默认它选对了。

### pipeline 构造器与 PipeOp 是两个命名空间

`ppl("robustify")` / `ppl("greplicate")` / `ppl("ovr")` / `ppl("stacking")` / `ppl("branch")` / `ppl("targettrafo")` / `ppl("convert_types")` 不在 `mlr_pipeops$keys()` 里，它们对应 `pipeline_*` 函数，**形参各不相同**且互不通用：用之前 `names(formals(mlr3pipelines:::pipeline_branch))` 现探，或直接试构造一次——报错信息里的形参名是可信的。

## 全局 R 编码铁律

本技能包遵循以下全局 R 编码铁律：

- **赋值**：统一 `=`，禁用 `<-`
- **管道**：数据处理用 **`|>`**，PipeOp 图连接用 **`%>>%`**
- **匿名函数**：用 `\(x)`，禁用 `function(x)`
- **分组汇总**：优先 `.by` 参数，避免 `group_by()` 常驻分组
- **禁用**：`ifelse()`、`merge()`、`gather()`/`spread()`、`*_at()`/`*_if()`/`*_all()`
- **命名**：函数名蛇形命名偏动词；每个函数专注单一计算
- **不混用** tidymodels 的 `recipe()` / `workflow()`

所有示例代码必须遵守以上铁律。

## 五大绝对红线

### 红线 1：测试集绝对隔离

开发期**禁止**对测试集做任何操作——预测、调参、`summary()`、`plot()`、数据审计全部禁止。只有模型流程完全定型后，**必须先询问用户并获许可**，才评估测试集。

```r
set.seed(7291)
split = partition(task, ratio = 0.7)  # 分类默认分层

# 开发期只用训练集
train_task = task$clone(deep = TRUE)$filter(split$train)

# split$test 在最终评估前不得使用！
```

**自检**：如果你在写 `$predict(task, row_ids = split$test)` 且用户未授权 → 立刻停下！

> **注意（references 一致性）**：`references/` 中部分示例（如 `advanced-workflows.md` 的 `at$predict(task, row_ids = split$test)`）展示的是「**获授权后的最终评估**」写法，不代表开发期可用；照抄任何含 `split$test` 的代码前，必须先获用户授权。

### 红线 2：R6 引用语义

mlr3 核心对象是 R6。`$select()`、`$filter()`、`$param_set$values` 等会**原地修改对象**。

```r
# 危险：直接污染原 task
task$select(cols)
task$filter(rows)

# 正确：需要保留原 task 时先深拷贝
task_model = task$clone(deep = TRUE)
task_model$select(cols)
```

重抽样/调优框架会自动 clone learner；但手动改 Task/Learner 参数时务必小心。

### 红线 3：特征工程必须在重抽样内部

禁止先在数据框或 task 外部处理后再建模。

| 错误 | 正确 |
|---|---|
| `df$x = scale(df$x)` 后建 Task | `po("scale") %>>% lrn(...)` |
| 全数据插补后建模 | `po("imputemedian")` / `po("imputeoor")` 等 |
| 全数据 PCA 后建模 | `po("pca")` |
| 全数据 SMOTE 后建模 | `po("smote")` 必须在图中 |
| 全数据特征选择后建模 | `po("filter")` 或 `auto_fselector()` |

### 红线 4：嵌套重抽样用于无偏比较，非执行超参数调优

嵌套重抽样（外层 `resample()` 包住 `auto_tuner()` 或 `auto_fselector()`）的唯一用途是**无偏比较不同算法/管道的泛化性能**——它回答"经调优后的某算法泛化误差有多大"。

嵌套重抽样本身**不执行最终的超参数调优**：调优发生在内层（`auto_tuner` 内部）。对 `auto_tuner` 对象调用 `$train(task)` 时，调优器在内层 CV 中搜索最优超参数，然后用最优参数在全训练集上拟合——这才是真正的超参数调优。嵌套重抽样只是反复做这件事，取平均作为无偏估计。

```r
# 超参数调优（训练最终模型用这个）
at$train(train_task)  # 内层 CV 调参 → 全训练集拟合最优参数

# 嵌套重抽样（报告泛化性能用这个）
rr_nested = resample(train_task, at, rsmp("cv", folds = 3))
rr_nested$aggregate(msr("classif.auc"))  # 无偏估计调参后泛化误差
```

### 红线 5：并行自动启用，但必须先量可用资源

不必征求授权即可开并行；**风险不是"擅自并行"，而是"凭空假设机器空闲"**。`future::availableCores()` 只报 CPU 额度上限、不报真实负载——本机实测恒为 20，同期内存已用 73%，说明机器并不空。所以开并行前两个数都要看：

```r
future::availableCores()    # CPU 额度（上限，非当前空闲）
ps::ps_system_memory()      # total / avail / percent：真实内存负载
future::plan("multisession", workers = n_workers)  # Windows 用 multisession
```

`n_workers` 取 `min(availableCores() - 1L, 内存装得下的折数)`；`percent` 已高、或用户在同一机器上同时干别的事，就主动下调，宁可退回单线程并说明原因。跑完 `future::plan("sequential")` 复原。（没装 `ps` 就别探测、按保守档取；`future` **没有** `availableMemory()`，`memory.limit()` 已不再支持——实测只告警并返回 `Inf`——两者都不能当负载信号。）

一条实测纪律：并行粒度是**重抽样迭代（折）**，所以外层一开并行，learner 内部线程必须压成 1——`set_threads(learner, n = 1L)`（单个 learner 或列表都行；线程参数名现探 `learner$param_set$ids(tags = "threads")`）。**写成 `set_threads(learner, nthreads = 1)` 是静默反向的**：形参只有 `(x, n, ...)`，错名被 `...` 吞掉、`n` 落到默认值 `availableCores()`，线程反而拉满。

## 默认工作流

1. 明确任务类型：二分类 / 多分类 / 回归；目标变量；样本量；是否分组或时间序列
2. 创建 `Task`，设置必要角色：`group`、`order`、`stratum` 等
3. 一次性划分训练/测试集，冻结 `split`；开发期只用 `split$train`
4. 选择指标和重抽样方案
5. 把所有预处理写入 PipeOp / GraphLearner（默认起点：`ppl("robustify")`）
6. 用 `resample()` / `benchmark()` / `auto_tuner()` / `auto_fselector()` 在训练集内开发
7. 如需调参流程的无偏性能，使用嵌套重抽样
8. 用户选定最终模型后，在全训练集拟合
9. 询问用户是否允许评估测试集；获许可后仅评估一次

## 最小代码骨架：分类

```r
library(mlr3verse)
library(data.table)

set.seed(7291)

task = as_task_classif(df, target = "outcome", positive = "yes")
split = partition(task, ratio = 0.7)
train_task = task$clone(deep = TRUE)$filter(split$train)

measures = msrs(c("classif.auc", "classif.ce", "classif.acc"))

# ppl("robustify") 一键稳健预处理（10+ 步骤，含插补/编码/去常数等）
glrn = ppl("robustify") %>>%
  lrn("classif.rpart", predict_type = "prob") |>
  as_learner()

rr = resample(train_task, glrn, rsmp("cv", folds = 5), store_models = TRUE)
rr$aggregate(measures)
```

## 最小代码骨架：回归

```r
library(mlr3verse)
library(data.table)

set.seed(7291)

task = as_task_regr(df, target = "outcome")
split = partition(task, ratio = 0.7)
train_task = task$clone(deep = TRUE)$filter(split$train)

measures = msrs(c("regr.rmse", "regr.mae", "regr.rsq"))

glrn = ppl("robustify") %>>%
  lrn("regr.rpart") |>
  as_learner()

rr = resample(train_task, glrn, rsmp("cv", folds = 5), store_models = TRUE)
rr$aggregate(measures)
```

## ppl("robustify") 默认预处理管线

**依赖包提示（防"运行即报错"）**：示例用到的模型/算子对应 R 包——`classif.glmnet`→`glmnet`、`classif.ranger`→`ranger`、`classif.kknn`→`kknn`、`classif.xgboost`→`xgboost`（注意是 `xgboost` 本身，学习器由 mlr3verse 附带的 `mlr3learners` 提供，`mlr3xgboost` 是另一套带预置调参空间的实现，装了会覆盖同名键）、`classif.svm`→`e1071`（mlr3verse 默认附带，但其 `cost`/`gamma` 是条件参数，见「调优：auto_tuner」陷阱说明）、`po("smote")`→`smotefamily`、`yeojohnson`/`boxcox` 分支→`bestNormalize`、ROC/PRC 可视化→`precrec`、`tnr("mbo")`→`mlr3mbo`（mlr3verse 已附带）、并行探测用的 `future::availableCores()`→`future` 与 `ps::ps_system_memory()`→`ps`（**这两个都不在 mlr3verse 的硬依赖里**，`packageDescription("mlr3verse")$Imports` 现场可查；装了 mlr3verse 再写 `future::` 就是运行即报错 `there is no package called 'future'`）。运行前先确认已安装（缺则 `install.packages(...)`）；未安装的模型/分支改用可用替代（如未装 bestNormalize 就去掉 yeojohnson 分支）。想核对某个键到底要哪个包：`mlr_learners$get("classif.xgboost")$packages`。还有一类不是"少装一个后端包"而是"整个提供方不在 CRAN"：`classif.lightgbm` / `regr.lightgbm` / `classif.catboost` 等由 `mlr3extralearners` 注册，该包不在 CRAN，官方通道是 mlr-org 的 r-universe（`install.packages("mlr3extralearners", repos = c(getOption("repos"), mlorg = "https://mlr-org.r-universe.dev"))`）；没装它时这些键根本不在 `mlr_learners$keys()` 里，写进文档的候选学习器清单前要先探测。

一键稳健预处理的 `ppl("robustify")` 展开是**含 14 个 PipeOp 的非线性 DAG**（不是线性串联），一次做掉：删常数 → 字符/有序因子转分类、日期转数值 → 数值列直方图采样插补 + 逻辑列经验分布插补 + 缺失指示器（这三路在 `featureunion_robustify` 处并行分叉再合并）→ 分类新水平视作缺失 → 修复因子水平 → 折叠稀有水平 → 独热编码 → 再删新增常数。节点名单与连边**现场探测**，别背：

```r
g = ppl("robustify")
g$edges                 # 14 x 4 边表（src / dst / src_params / dst_params），里面能看到 featureunion_robustify 分叉
g$param_set$ids()       # 35 个 "节点名.参数名" 形式的可调 id；Graph 上 $nodes / $pipe 是 NULL，别找它们
g$param_set$values      # 已经装了 28 条默认值（不是空 list），要改就在它上面覆盖
```

要单独改某一环（换成 treatment 编码 → `encode.method`；调折叠阈值 → `collapsefactors.no_collapse_above_prevalence` / `.target_level_count`；改 `missind.which`），先从 `$ids()` 里按 `节点名.参数名` 找到 id，再在构造好的 learner 上 `glrn$param_set$values[["encode.method"]] = "treatment"`（默认值用 `mlr_pipeops$get("collapsefactors")$param_set$default` 看，不要凭记忆写数字）。

```r
glrn = ppl("robustify") %>>%   # task=task, learner=lrn 可选
  lrn("classif.glmnet", predict_type = "prob") |>
  as_learner()
```

## 重抽样与评估

| 场景 | 推荐 |
|---|---|
| 中小数据 | `rsmp("cv", folds = 5)` 或 10 |
| 大数据（≥ 10k） | 训练集内 holdout |
| 分组相关观测 | 设置 `group` 角色后 CV（实测自动按组切分） |
| 时间序列 | 按时间位置显式切分 + `rsmp("custom")` 滚动折——内置字典**无** rolling_origin，`order` 角色不改变随机 CV 切分方式 |

| 任务 | 首选指标 | 补充 |
|---|---|---|
| 二分类 | `classif.auc`, `classif.ce` | 不平衡加 `classif.prauc`, `classif.fbeta` |
| 多分类 | `classif.acc`, macro AUC | `classif.mbrier` |
| 回归 | `regr.rmse`, `regr.rsq` | `regr.mae` |

### 评估必附可视化

数值指标之外必须附对应图形（用训练集内 CV 预测绘制；测试集图须获授权后画）：

| 任务 | 必附 |
|---|---|
| 二分类 | ROC（不平衡换 PR）+ 阈值相关 `autoplot(pred, type = "threshold")` |
| 回归 | 观测 vs 预测散点 + 残差图 |

```r
# ROC/PRC 图依赖 R 包 precrec（mlr3verse 不自带，缺则 install.packages("precrec")）
autoplot(rr$prediction(), type = "roc")   # 二分类；不平衡改 type = "prc"
```

回归的 obs-vs-pred / 残差 ggplot 写法、benchmark 箱线图见 `references/evaluation.md`。

## PipeOp / GraphLearner 特征工程

### 基础语法

图学习器用 `%>>%` 连接 PipeOp，末端 `|> as_learner()` 转为 Learner：

```r
glrn = po("scale", affect_columns = selector_type(c("numeric", "integer"))) %>>%
  po("pca", rank. = 2) %>>%
  lrn("classif.rpart") |>
  as_learner()
```

`selector_type("numeric")` **选不中 `integer` 列**（整数在 task 里是独立类型），要连整数一起缩放必须写 `selector_type(c("numeric", "integer"))`——否则 `po("scale")` 静默跳过 `1:10` 这类列。

| 模型 | 建议 PipeOp |
|---|---|
| 线性/逻辑/glmnet | `removeconstants` + `imputemean`/`imputemode` + `encode("treatment")` + `scale` |
| KNN/SVM/NN | `removeconstants` + 插补 + `encode("one-hot")` + `scale` |
| 树/随机森林/提升树 | 通常不需标准化；但 ranger / xgboost **不接受 factor 列**（报 `unsupported feature types: factor`），仍需 `encode` 与插补 |
| 不平衡分类 | `po("classbalancing")` 或 `po("smote")`（必须在图中） |

### mlr3pipelines 高级能力

GraphLearner 本质上就是一个 Learner——可被 `resample()`、`benchmark()`、`auto_tuner()`、`auto_fselector()` 等任何需要 Learner 的接口直接使用。mlr3pipelines 支持：

- **复杂 DAG（非简单线性流）**：用 `gunion()` 并行分支、`%>>%` 串联，搭建有向无环图
- **分支路由调参（Branch Selection）**：用 `ppl("branch")` + `to_tune(p_fct(...))` 让调优器自动选择最优预处理路径或最优学习器
- **堆叠集成（Stacking）**：`ppl("stacking")` 或自定义图中学习器集成，自动防泄露
- **图超参数联合调优**：PipeOp 参数带前缀入图后，与学习器参数一起加入 `to_tune()`

GraphLearner 一旦创建，就按普通学习器一样使用，**天然防数据泄露**——所有预处理参数均在重抽样内部学习。详见 `references/advanced-workflows.md`。

### 备选路径调参速览

用 `ppl("branch")` + `to_tune(...)` 让调优器自动选择最优预处理路径和最优学习器。分支选择参数是 `ParamFct`，直接在 learner 参数集上赋 `to_tune()` 即可（等价写法：用 `ps()` + `tune()` 显式声明搜索空间，见 `references/advanced-workflows.md` §2.2）：

**缩写来源**：`pos()` = `mlr3pipelines::pos`（特征位置选择器）、`lrns()` = `mlr3::lrns`（批量构造学习器列表）、`gunion()` = `mlr3pipelines::gunion`（图并行合并）。

```r
# 两个分支：预处理分支（nop/pca/yeojohnson）+ 学习器分支（rpart/kknn）
# 注意：yeojohnson 分支需要 R 包 bestNormalize，未安装时请去掉该分支
prep = ppl("branch", pos(c("nop", "pca", "yeojohnson")))
prep$update_ids(prefix = "prep_")
graph = prep %>>%
  ppl("branch", lrns(c("classif.rpart", "classif.kknn")))

glrn = as_learner(graph)
glrn$param_set$values$prep_branch.selection = to_tune(c("nop", "pca", "yeojohnson"))
glrn$param_set$values$branch.selection = to_tune(c("classif.rpart", "classif.kknn"))

at = auto_tuner(
  tuner      = tnr("random_search"),
  learner    = glrn,
  resampling = rsmp("cv", folds = 4),
  measure    = msr("classif.ce"),
  term_evals = 20
)
at$train(train_task)
at$tuning_result  # 看哪个预处理路径 + 学习器组合最优
```

分支内的学习器还要再调超参数（如 `classif.kknn.k`）时，用 `ps()` 显式声明搜索空间并加 `depends` 条件（`classif.kknn.k = p_int(1, 32, depends = branch.selection == "classif.kknn")`），写法见 `references/advanced-workflows.md` §2.2。

## 调优：auto_tuner

> **classif.svm 条件参数陷阱（必读）**：`cost` / `gamma` 是条件参数——`cost` 依赖 `type == "C-classification"`，`gamma` 依赖 `kernel ∈ {polynomial, radial, sigmoid}`。对它们 `to_tune()` 前**必须显式设置 `type` 与 `kernel`**，否则报 `Assertion on 'xs' failed: cost can only be set if type == C-classification...`。

```r
learner = lrn("classif.svm",
  type   = "C-classification",          # 必须显式设置（cost 的前置条件）
  kernel = "radial",                     # 必须显式设置（gamma 的前置条件）
  cost   = to_tune(1e-5, 1e5, logscale = TRUE),
  gamma  = to_tune(1e-5, 1e1, logscale = TRUE),
  predict_type = "prob"
)

at = auto_tuner(
  tuner      = tnr("random_search"),
  learner    = learner,
  resampling = rsmp("cv", folds = 4),
  measure    = msr("classif.auc"),
  term_evals = 30
)

at$train(train_task)
at$tuning_result
```

调参器选择：小空间用 `grid_search`，高维用 `random_search`，昂贵模型用 `mbo`。

两种等价写法（按上下文任选）：
- `at$train(train_task)` — 传入已构造好的训练任务
- `at$train(task, row_ids = split$train)` — 传完整 task + 训练行号（references 常用，便于继续用 `split$test` 预测）

## 基准测试与嵌套重抽样

### 简单基准测试（未调参）

多模型比较必须相同训练任务和重抽样：

```r
design = benchmark_grid(
  tasks       = train_task,
  learners    = list(glrn_1, glrn_2, glrn_3),
  resamplings = rsmp("cv", folds = 5)
)
bmr = benchmark(design, store_models = TRUE)
bmr$aggregate(measures)
```

### 进阶：比较经调优的算法

更具现实意义的比较是把 **auto_tuner + learner 整体**塞进 `benchmark_grid()`——比的是「各自调好参之后」哪个算法更强，而不是裸参数下的强弱。写法与 `at_svm` / `at_rf` 完整示例见 `references/advanced-workflows.md` §1（骨架回归用例 6 实跑的就是它）；要点只有三条：`auto_tuner()` 本身就是 Learner，可直接进 `learners = list(at_svm, at_rf)`；内层调参重抽样与外层比较重抽样是**两件事**，各配各的；外层仍只用 `train_task`。

### 嵌套重抽样：报告调参流程无偏泛化性能

```r
outer_cv = rsmp("cv", folds = 3)
rr_nested = resample(train_task, at, outer_cv, store_models = TRUE)
rr_nested$aggregate(msr("classif.auc"))
```

## 错误处理与日志

封装与兜底**只能通过 `$encapsulate()` 方法**设置：`encapsulate` 是方法名、`encapsulation` 与 `fallback` 是只读 binding，任何赋值形式（含构造参数）都运行即报错。`fallback` 形参没有默认值，必须显式给——`default_fallback(learner)` 已导出，按任务类型给 `classif.featureless` / `regr.featureless`。

```r
learner$encapsulate("evaluate", default_fallback(learner))  # train / predict 同时封装
lgr::get_logger("mlr3")$set_threshold("warn")
```

`resample()` 只要有一折训练报错就**取消全部迭代并抛错**，不返回部分结果。封装后同样的折由 fallback 顶上、整体跑完，`rr$errors` 留下逐折记录——但那几折的分数来自兜底模型，不能当成被评估管道的真实性能。典型触发场景（bootstrap 分析集与 PipeOp 主键断言冲突等）见 `references/resampling.md` §10。

## 知识路由表

skill.md 保持精简；遇到以下具体需求时，读取对应知识文件：

| 需求 | 文件 |
|---|---|
| 数据分割（常规划分、时间序列、分组） | `references/data-spending.md` |
| 重抽样方法（CV/重复CV/滑窗/分组） | `references/resampling.md` |
| 特征工程总览 | `references/feature-engineering.md` |
| 分类特征处理 | `references/feature-engineering/categorical.md` |
| 数值特征处理 | `references/feature-engineering/numeric.md` |
| 缺失值插补 | `references/feature-engineering/missing-data.md` |
| 相关性削减 | `references/feature-engineering/correlation.md` |
| 模型评估指标与可视化 | `references/evaluation.md` |
| 超参数调优 | `references/tuning.md` |
| 进阶工作流（调参器benchmark、图学习器调参/分支选择、不平衡+调优、特征选择+调优联合、早停+混合调优） | `references/advanced-workflows.md` |

## 常见反模式

| 避免 | 推荐 |
|---|---|
| Task 外全局标准化/插补/PCA/SMOTE | PipeOp / GraphLearner |
| 直接 `task$select()` 污染原对象 | 先 `$clone(deep = TRUE)` |
| PipeOp 用 `|>` 串联 | `%>>%` |
| 手写嵌套 CV | `auto_tuner()` + 外层 `resample()` |
| 假设机器空闲就开满并行 | 先探测 `availableCores()` + `ps_system_memory()` 再定 workers |
| 开发期评估测试集 | 完全定型后经用户授权 |
| 用 123、42 等常见种子 | 用 3847、7291 等随机值 |

## 自检清单

- [ ] 测试集是否完全隔离，直到用户授权？
- [ ] 修改 Task 前是否需要 `$clone(deep = TRUE)`？
- [ ] 所有预处理是否封装进 PipeOp / GraphLearner？
- [ ] 图管道是否使用 `%>>%`，末端是否 `as_learner()`？
- [ ] 调参/特征选择是否使用 `auto_tuner()` / `auto_fselector()`？
- [ ] 若要报告调参流程泛化性能，是否使用嵌套重抽样？
- [ ] 并行前是否先探测可用资源（核心数 + 内存负载）并按负载定 workers、外层并行时把 learner 内部线程压成 1？
- [ ] 种子是否避开了 1、42、123 等常见值？
- [ ] 嵌套重抽样是否仅用于无偏比较，超参数调优是否用 `$train(task)`？
- [ ] 对复杂 GraphLearner 是否利用了 `ppl("branch")` 分支路由调参？
- [ ] 不平衡处理（SMOTE 等）是否封装在图中并用 `auto_tuner` 确保每折独立采样？
- [ ] 代码是否遵守全局 R 编码铁律（`=`、`|>`/`%>>%`、`\(x)`、`.by`）？
- [ ] 示例代码改动后运行 `scripts/verify_examples.R`，20 个案例全 PASS？
