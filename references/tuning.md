# 超参数调优与特征选择（mlr3verse）

调参和特征选择都是模型开发的一部分，必须只在训练集内部完成。若要报告调参流程真实性能，必须使用嵌套重抽样。

## 1. 搜索空间

### 1.1 在 learner 中直接声明

```r
learner = lrn("classif.svm",
  cost = to_tune(1e-5, 1e5, logscale = TRUE),
  kernel = to_tune(c("polynomial", "radial")),
  predict_type = "prob"
)
```

### 1.2 用 `ps()` 显式声明

```r
search_space = ps(
  cost = p_dbl(1e-5, 1e5, logscale = TRUE),
  kernel = p_fct(c("polynomial", "radial")),
  degree = p_int(1, 3, depends = kernel == "polynomial")
)
```

### 1.3 使用预定义空间

```r
library(mlr3tuningspaces)
search_space = lts("classif.svm.default")
```

## 2. auto_tuner：推荐入口

`auto_tuner()` 把"内层重抽样调参 + 最佳参数全训练集拟合"封装成一个 learner。

```r
at = auto_tuner(
  tuner = tnr("random_search"),
  learner = learner,
  resampling = rsmp("cv", folds = 4),
  measure = msr("classif.auc"),
  term_evals = 30
)

at$train(train_task)
at$tuning_result
as.data.table(at$archive)
```

不要在开发期用 `split$test` 调参。

## 3. 调参器选择

| 场景 | 推荐 | 备注 |
|---|---|---|
| 小空间、离散参数 | `tnr("grid_search")` | 可复现，可能昂贵 |
| 高维空间 | `tnr("random_search")` | 默认稳健选择 |
| 昂贵模型 | `tnr("mbo")` | 需 `mlr3mbo` |
| 大量候选配置筛选 | `tnr("irace")` | 适合竞赛式淘汰 |

终止条件常用：

```r
trm("evals", n_evals = 30)
trm("run_time", secs = 600)
trm("combo", list(trm("evals", n_evals = 50), trm("run_time", secs = 1800)))
```

## 4. 调图学习器

可同时调预处理和模型参数：

```r
glrn = po("encode", method = to_tune(c("treatment", "one-hot"))) %>>%
  po("pca", rank. = to_tune(2, 10)) %>>%
  lrn("classif.svm",
    cost = to_tune(1e-5, 1e5, logscale = TRUE),
    predict_type = "prob"
  ) |>
  as_learner()

at = auto_tuner(
  tuner = tnr("random_search"),
  learner = glrn,
  resampling = rsmp("cv", folds = 4),
  measure = msr("classif.auc"),
  term_evals = 30
)
```

## 5. 初始模型建议

除非用户指定，建议至少比较两类差异大的模型：

### 5.1 正则化线性模型

```r
learner_glmnet = ppl("robustify") %>>%
  po("scale") %>>%
  lrn("classif.glmnet",
    alpha = to_tune(0, 1),
    lambda = to_tune(1e-5, 1, logscale = TRUE),
    predict_type = "prob"
  ) |>
  as_learner()
```

### 5.2 提升树

```r
learner_xgb = ppl("robustify") %>>%
  lrn("classif.xgboost",
    nrounds = to_tune(100, 2000),
    eta = to_tune(1e-4, 0.5, logscale = TRUE),
    max_depth = to_tune(1, 10),
    predict_type = "prob"
  ) |>
  as_learner()
```
