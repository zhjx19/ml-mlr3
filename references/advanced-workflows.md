# 进阶工作流（mlr3verse）

本文档涵盖 mlr3verse 的高级建模工作流，与技能包核心原则（测试集隔离、GraphLearner 防泄露、`%>>%` 管道等）配套使用。

## 1. 自动调参器 + 基准测试

简单 benchmark 仅比较未经调优的基学习器。更具现实意义的做法是将 **auto_tuner + learner** 整体纳入 benchmark——比较「经超参数调优后」的不同算法的综合性能。

```r
task = tsk("sonar")

# SVM 自动调参器
lrn_svm = lrn("classif.svm", type = "C-classification",
              kernel = "radial", predict_type = "prob")
ps_svm = ps(cost = p_dbl(1, 1e5, logscale = TRUE),
            gamma = p_dbl(1e-5, 1))
at_svm = auto_tuner(
  tuner = tnr("random_search"),
  learner = lrn_svm,
  search_space = ps_svm,
  resampling = rsmp("cv", folds = 4),
  measure = msr("classif.auc"),
  term_evals = 10)

# 随机森林自动调参器
lrn_rf = lrn("classif.ranger", predict_type = "prob")
ps_rf = ps(num.trees = p_int(2, 10, trafo = \(x) 5 * x),
           mtry = p_int(3, 20), min.node.size = p_int(2, 10))
at_rf = auto_tuner(
  tuner = tnr("random_search"),
  learner = lrn_rf,
  search_space = ps_rf,
  resampling = rsmp("cv", folds = 4),
  measure = msr("classif.auc"),
  term_evals = 10)

# benchmark 比较调优后的算法
set.seed(5241)
design = benchmark_grid(tasks = task, learners = list(at_svm, at_rf),
                        resamplings = rsmp("cv", folds = 5))
bmr = benchmark(design)
bmr$aggregate(msr("classif.auc"))            # 平均性能
autoplot(bmr, measure = msr("classif.auc"))  # 箱线图
```

更进一步，可将图学习器的自动调参器（预处理 + 算法 + 调优）整体纳入 benchmark，比较「哪一套完整建模方案在特定任务上综合表现最优」。

## 2. 图学习器调参

GraphLearner 可像普通 learner 一样接入 `auto_tuner()`，支持两种调参方式。

### 2.1 调参图超参数

对顺序管道中的 PipeOp 参数和学习器参数进行联合调参。超参数名自动带前缀。

```r
task = tsk("sonar")

# 主成分降维 + K 近邻，联合调参主成分数和邻居数
graph = po("pca", rank. = to_tune(2, 20)) %>>%
  lrn("classif.kknn", k = to_tune(1, 32))
glrn = as_learner(graph)

glrn$param_set$ids()  # 查看带前缀的超参数名

glrn_tuned = auto_tuner(
  tuner = tnr("random_search"),
  learner = glrn,
  resampling = rsmp("cv", folds = 5),
  measure = msr("classif.ce"),
  term_evals = 10)

# 嵌套重抽样比较调参和未调参的图
glrn_untuned = po("pca") %>>% lrn("classif.kknn")
design = benchmark_grid(task, c(glrn_tuned, glrn_untuned),
                        rsmp("cv", folds = 4))
bmr = benchmark(design)
bmr$aggregate()
```

### 2.2 调参备选路径（Branch Selection）

对于不确定是否包含某些操作的管道，可调参决定应使用哪些 PipeOp 或学习器——即「组合算法选择和超参数调优」。

> 速记版：若只需在 learner 上直接声明分支选择，可用 `glrn$param_set$values$...selection = to_tune(c(...))` 直赋（见 `SKILL.md`「备选路径调参速览」）。本小节展示用 `ps()` 显式构建搜索空间的完整写法，二者等价。

```r
task = tsk("sonar")

# 预处理分支：不处理 / PCA / Yeo-Johnson
# 注意：yeojohnson 分支需安装 R 包 bestNormalize（缺包会在运行时报错）
prep = ppl("branch", pos(c("nop", "pca", "yeojohnson")))
prep$update_ids(prefix = "prep_")

# 学习器分支：决策树 / K 近邻
graph = prep %>>%
  ppl("branch", lrns(c("classif.rpart", "classif.kknn")))

glrn = as_learner(graph)

# 搜索空间：选择性调参 + 条件依赖
searchspace = ps(
  prep_branch.selection = p_fct(c("nop", "pca", "yeojohnson")),
  branch.selection = p_fct(c("classif.rpart", "classif.kknn")),
  classif.kknn.k = p_int(1, 32,
    depends = branch.selection == "classif.kknn"))

set.seed(5241)
instance = tune(
  tuner = tnr("grid_search"),
  task = task,
  learner = glrn,
  resampling = rsmp("cv", folds = 5),
  measures = msr("classif.ce"),
  search_space = searchspace)

instance$result
autoplot(instance)
```

## 3. 不平衡处理 + 超参数调优

### 核心原则

不平衡处理（如 SMOTE）只能应用于训练集，绝不能影响验证集或测试集。

### 正确做法

将 SMOTE 与学习器封装为图学习器，用 `auto_tuner` 自动实现「每折独立采样、最终模型独立训练」：

- **调参阶段**：每次 CV 折叠中，SMOTE 仅作用于（内）训练集，验证集保持原始分布
- **训练最终模型阶段**：调参完成后，自动使用最优参数，对全（外）训练集重新应用 SMOTE 并训练
- **预测阶段**：模型在未修改的原始数据上预测

```r
task = tsk("spam")
# 注意：po("smote") 依赖外部 R 包 smotefamily，须先安装，否则报错：
#       Package 'smotefamily' required but not installed

set.seed(5241)
split = partition(task, ratio = 0.8)

# SMOTE + 决策树 封装为图学习器
glrn = po("smote", dup_size = 1) %>>%
  lrn("classif.rpart") |>
  as_learner()

# 超参数调优：剪枝复杂度
at = auto_tuner(
  tuner = tnr("random_search"),
  learner = glrn,
  resampling = rsmp("cv", folds = 5),
  measure = msr("classif.ce"),
  search_space = ps(classif.rpart.cp = p_dbl(0, 0.1)),
  term_evals = 10)

at$train(task, row_ids = split$train)
at$tuning_result

# 最终模型在原始测试集上预测
pred_test = at$predict(task, row_ids = split$test)
```

**关键机制**：通过将 SMOTE 与学习器封装为图学习器，`mlr3verse` 自动实现每折独立采样与最终模型独立训练，无需手动干预。

## 4. 特征选择与超参数的联合调优

最优特征子集与最优模型参数往往深度耦合。借助 mlr3 管道，保留特征数可作为 `to_tune()` 参数与模型参数联合优化。

```r
task = tsk("sonar")

set.seed(5241)
split = partition(task, ratio = 0.75)

# 特征选择 + 随机森林联合调优管道
graph = po("filter", filter = flt("information_gain"),
            filter.nfeat = to_tune(5, 50)) %>>%
  po("learner", lrn("classif.ranger", predict_type = "prob",
                      num.trees = to_tune(100, 500),
                      mtry = to_tune(1, 10)))
glrn = as_learner(graph)

at = auto_tuner(
  tuner = tnr("random_search", batch_size = 5),
  learner = glrn,
  resampling = rsmp("cv", folds = 5),
  measure = msr("classif.auc"),
  term_evals = 20)

set.seed(4817)
at$train(task, row_ids = split$train)
at$tuning_result

pred = at$predict(task, row_ids = split$test)
pred$score(msr("classif.auc"))
```

**对比分步操作**：先选特征再调参，人工决策成本高且可能错过更优组合。联合搜索用可控的计算开销（固定 `term_evals`）一次性完成试探。

## 5. 早停与内外混合调优

### 早停机制

提升树模型迭代构建，需启用早停防止过拟合。训练时监控验证集性能，连续若干轮无改善则终止。

### 混合调优策略

- **外层循环**：调参器（如随机搜索）探索不同超参数组合
- **内层循环**：早停为每个超参数组合自动确定最佳迭代轮次

最终模型兼具最优超参数结构与最佳停止节点。

```r
library(mlr3verse)

# 用内置二分类数据集（含因子特征）演示，避免外部 csv 依赖
task = tsk("german_credit")

# XGBoost 不支持分类特征，用 ppl("robustify") 自动编码 + 去常数
graph = ppl("robustify", task = task) %>>%
  lrn("classif.xgboost", predict_type = "prob",
      max_depth = to_tune(3, 8),
      eta = to_tune(0.01, 0.3),
      nrounds = to_tune(upper = 300, internal = TRUE),
      early_stopping_rounds = 30,
      eval_metric = "logloss")
glrn = as_learner(graph)

# 关键：验证集只能用 set_validate() 设置——learner 构造参数里没有 validate，写 lrn(..., validate = 0.2) 会报错
# 0.2 表示 20% 训练数据作为内部验证集，用于早停监控
set_validate(glrn, validate = 0.2)

set.seed(5241)
split = partition(task, ratio = 0.7)

at = auto_tuner(
  tuner = tnr("random_search"),
  learner = glrn,
  resampling = rsmp("cv", folds = 5),
  measure = msr("classif.auc"),
  term_evals = 20)

set.seed(4817)
at$train(task, row_ids = split$train)
at$tuning_result   # 含 internal_tuned_values 列出每轮早停选出的 nrounds
```

**早停参数说明**：

- `nrounds(internal = TRUE)`：将迭代轮次下放给内层调优（早停自动确定停止轮次）
- `early_stopping_rounds = 30`：连续 30 轮无改善则停止
- `eval_metric = "logloss"`：内层用连续概率指标（比离散 error 更早捕捉过拟合趋势）
- `set_validate(glrn, validate = 0.2)`：用 20% 训练数据作内部验证集——只能这样设置，learner 构造参数中已无 `validate`

**注**：`set_validate(..., validate = "test")` 可复用外层测试集提升数据利用率，但会导致数据泄露并高估泛化性能，仅限计算资源极度受限时的探索性分析。
