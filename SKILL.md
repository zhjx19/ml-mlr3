---
name: ml-mlr3
description: >-
  Use when 用户需要用 R mlr3verse 框架做表格数据机器学习建模——构建预测模型、比较算法、
  调优超参数、做特征工程或特征选择，或提到 mlr3、mlr3pipelines、mlr3tuning、mlr3fselect、
  GraphLearner、PipeOp、auto_tuner、auto_fselector 等关键词时使用。
  不要用于：深度学习、非表格数据（图像/文本/NLP）；tidymodels 工作流（改用 tidymodels 生态技能）；
  轻量探索性分组建模（dplyr nest + map 即可）；数据清洗本身。
license: Apache-2.0
---

# mlr3verse 表格数据机器学习建模


## 技能定位与边界

本技能包覆盖 mlr3verse 机器学习建模全流程：数据分割 → PipeOp 特征工程 → 模型选择 → 调优/特征选择 → 嵌套重抽样评估 → 最终拟合。

**不在范围内**：深度学习、非表格数据（图像/文本/NLP）、tidymodels 工作流（改用 tidymodels 生态技能）。

## API 现场校验（不背版本号）

mlr3 生态迭代快，本技能不维护版本对照表：**版本号全文只出现在下面这一行实测记录里**，它回答"这些示例最近何时、在什么环境跑通"，不回答"哪个 API 从哪个版本起存在"。规则只有一条：**照抄任何对象名/参数名之前，先当场探测它是否存在**。示例的可执行契约由 `scripts/verify_examples.R`（17 例实跑）和 `scripts/run_evals.mjs`（静态断言）把守——改完示例代码这两个都必须重跑，跑通后刷新这行记录。

> 实测记录：2026-09-26 · R 4.6.1 / mlr3 1.8.0 / mlr3pipelines 0.12.0 / mlr3tuning 1.7.0 / mlr3fselect 1.7.0 / paradox 1.0.1 · `verify_examples.R` 17/17 PASS

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

两条实测确认的纪律：`AutoTuner` / `AutoFselector` 的 `$clone(deep = TRUE)` 得到的是**全新未训练**对象（`$model`、`$archive` 为空），可以放心各自训练互不干扰——但 `Task` 的 `$select()` / `$filter()` 和 `$param_set$values` 仍是原地修改（见红线 2）。`fs("rfecv")` 配最小化指标（`classif.ce` 等）时，必须自己核对 `selection_result` 里特征数与性能的走向是否单调，别默认它选对了。

### pipeline 构造器与 PipeOp 是两个命名空间

`ppl("robustify")` / `ppl("greplicate")` / `ppl("ovr")` / `ppl("stacking")` / `ppl("branch")` / `ppl("targettrafo")` / `ppl("convert_types")` 不在 `mlr_pipeops$keys()` 里，它们对应 `pipeline_*` 函数，形参各不相同：`greplicate(graph, n)`、`branch(graphs)`、`ovr(graph)`、`stacking(base_learners, super_learner)`、`targettrafo(graph)`、`convert_types(type_from, type_to)`。用之前 `names(formals(mlr3pipelines:::pipeline_x))` 或试构造一次，报错信息里的形参名是可信的。

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

### 红线 5：并行计算必须授权

不得自动启用并行。流程：`parallel::detectCores()` → 询问用户 → 获许可后才设 `future::plan("multisession", workers = n)`。Windows 用 `multisession`。

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

**依赖包提示（防"运行即报错"）**：示例用到的模型/算子对应 R 包——`classif.glmnet`→`glmnet`、`classif.ranger`→`ranger`、`classif.kknn`→`kknn`、`classif.svm`→`e1071`（mlr3verse 默认附带，但其 `cost`/`gamma` 是条件参数，见「调优：auto_tuner」陷阱说明）、`po("smote")`→`smotefamily`、`yeojohnson` 分支→`bestNormalize`、ROC/PRC 可视化→`precrec`。运行前先确认已安装（缺则 `install.packages(...)`）；未安装的模型/分支改用可用替代（如未装 bestNormalize 就去掉 yeojohnson 分支）。

一键稳健预处理的 `ppl("robustify")` 生成一个**含 14 个 PipeOp 的非线性 DAG**（非简单线性流），覆盖大多数缺失值插补和因子编码场景。按执行顺序的核心节点：

1. `removeconstants_prerobustify` — 删除常数特征
2. `char_to_fct` — 字符 → 分类
3. `POSIXct_to_dbl` — 日期/时间 → 数值
4. `ord_to_fct` — 有序因子 → 分类
5. `imputehist` — 数值特征直方图采样插补
6. `impute_logicals` — 逻辑特征经验分布采样插补
7. `missind` — 添加缺失值指示器
8. `featureunion_robustify` — 并行合并上面的分支（这是 DAG 分叉点）
9. `imputeoor` — 分类特征新水平编码缺失
10. `fixfactors` — 修复分类水平（train/predict 对齐）
11. `imputesample` — 插补修复水平引入的分类缺失
12. `collapsefactors` — 折叠稀有关卡（默认 max 1000）
13. `encode` — 分类特征独热编码
14. `removeconstants_postrobustify` — 删除新增的常数特征

注意：这是**非线性图**，含 `featureunion` 并行分支，不是简单的线性串联。

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

若需为分支内的学习器再加超参数（如 `classif.kknn.k`），用 `depends` 约束：

```r
glrn$param_set$add(
  ps(classif.kknn.k = p_int(1, 32, depends = branch.selection == "classif.kknn"))
)
```

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

更具现实意义的比较将 **auto_tuner + learner** 整体纳入 benchmark，比较「经超参数调优后」的不同算法：

```r
# 每个 learner 都包装为 auto_tuner
at_svm = auto_tuner(
  tuner = tnr("random_search"),
  learner = lrn("classif.svm", type = "C-classification",
                kernel = "radial", predict_type = "prob"),
  search_space = ps(cost = p_dbl(1, 1e5, logscale = TRUE),
                    gamma = p_dbl(1e-5, 1)),
  resampling = rsmp("cv", folds = 4),
  measure = msr("classif.auc"),
  term_evals = 10)

at_rf = auto_tuner(
  tuner = tnr("random_search"),
  learner = lrn("classif.ranger", predict_type = "prob"),
  search_space = ps(num.trees = p_int(2, 10, trafo = \(x) 5 * x),
                    mtry = p_int(3, 20)),
  resampling = rsmp("cv", folds = 4),
  measure = msr("classif.auc"),
  term_evals = 10)

# benchmark 比较调优后的算法（只用训练集，勿触碰测试集）
design = benchmark_grid(tasks = train_task, learners = list(at_svm, at_rf),
                        resamplings = rsmp("cv", folds = 5))
bmr = benchmark(design)
bmr$aggregate(msr("classif.auc"))
autoplot(bmr, measure = msr("classif.auc"))
```

### 嵌套重抽样：报告调参流程无偏泛化性能

```r
outer_cv = rsmp("cv", folds = 3)
rr_nested = resample(train_task, at, outer_cv, store_models = TRUE)
rr_nested$aggregate(msr("classif.auc"))
```

## 错误处理与日志

```r
learner$encapsulate = c(train = "evaluate", predict = "evaluate")
learner$fallback = lrn("classif.featureless")
lgr::get_logger("mlr3")$set_threshold("warn")
```

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
| 自动开并行 | 先询问用户 |
| 开发期评估测试集 | 完全定型后经用户授权 |
| 用 123、42 等常见种子 | 用 3847、7291 等随机值 |

## 自检清单

- [ ] 测试集是否完全隔离，直到用户授权？
- [ ] 修改 Task 前是否需要 `$clone(deep = TRUE)`？
- [ ] 所有预处理是否封装进 PipeOp / GraphLearner？
- [ ] 图管道是否使用 `%>>%`，末端是否 `as_learner()`？
- [ ] 调参/特征选择是否使用 `auto_tuner()` / `auto_fselector()`？
- [ ] 若要报告调参流程泛化性能，是否使用嵌套重抽样？
- [ ] 并行计算是否先获得用户授权？
- [ ] 种子是否避开了 1、42、123 等常见值？
- [ ] 嵌套重抽样是否仅用于无偏比较，超参数调优是否用 `$train(task)`？
- [ ] 对复杂 GraphLearner 是否利用了 `ppl("branch")` 分支路由调参？
- [ ] 不平衡处理（SMOTE 等）是否封装在图中并用 `auto_tuner` 确保每折独立采样？
- [ ] 代码是否遵守全局 R 编码铁律（`=`、`|>`/`%>>%`、`\(x)`、`.by`）？
- [ ] 示例代码改动后运行 `scripts/verify_examples.R`，17 个案例全 PASS？
