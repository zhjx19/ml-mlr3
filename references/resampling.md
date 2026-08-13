# 重抽样策略（mlr3verse）

重抽样用于在训练集内部估计样本外性能。它是开发期评估模型、特征工程、调参流程的主要工具，不需要触碰测试集。

## 1. 选择矩阵

| 数据场景 | 推荐重抽样 | 说明 |
|---|---|---|
| 中小数据 | `rsmp("cv", folds = 5 或 10)` | 默认选择，方差较低 |
| 模型很慢 / 数据较大 | `rsmp("holdout")` | 快速但方差较高 |
| 最终训练期稳健比较 | `rsmp("repeated_cv")` | 更稳定但计算量大 |
| 同一实体多条记录 | group-aware CV | 先设置 `group` 角色 |
| 时间序列 | `rsmp("rolling_origin")` | 避免未来预测过去 |
| 调参流程真实性能 | 外层 CV + `auto_tuner()` | 嵌套重抽样 |

## 2. V 折交叉验证

```r
set.seed(2954)
cv5 = rsmp("cv", folds = 5)

rr = resample(train_task, learner, cv5, store_models = TRUE)
rr$aggregate(msr("classif.auc"))
as.data.table(rr$score(msr("classif.auc")))
```

要点：

- 开发期传入的应是 `train_task`，不是完整 task。
- 分类任务需要概率指标时，learner 必须支持 `predict_type = "prob"`。
- `store_models = TRUE` 便于诊断，但会占用更多内存。

## 3. 重复交叉验证

```r
set.seed(8173)
rcv = rsmp("repeated_cv", folds = 10, repeats = 5)
rr = resample(train_task, learner, rcv)
rr$aggregate(msr("classif.auc"))
```

适合最终比较少数候选模型，不适合早期大量探索。

## 4. Holdout

```r
set.seed(6401)
ho = rsmp("holdout", ratio = 0.8)
rr = resample(train_task, learner, ho)
rr$aggregate(msr("regr.rmse"))
```

适合大数据或昂贵模型。不要把 holdout 误认为最终测试集：它仍然属于训练集内部开发预算。

## 5. 分组数据

如果观测不独立，先设置 group 角色：

```r
task$set_col_roles("patient_id", roles = "group")
train_task = task$clone(deep = TRUE)$filter(split$train)

cv = rsmp("cv", folds = 5)
rr = resample(train_task, learner, cv)
```

目标：同一个 group 不应同时出现在某次训练折和验证折中。

## 6. 时间序列：滚动原点

时间序列要保持时间方向：

```r
task$set_col_roles("date_col", roles = "order")

ro = rsmp("rolling_origin",
  folds = 10,
  fixed_window = FALSE,
  window_size = 0.6,
  horizon = 1
)

rr = resample(train_task, learner, ro)
```

在写代码前确认数据已按时间排序、预测 horizon 与业务目标一致。

## 7. 保存与提取预测

```r
rr = resample(train_task, learner, cv5, store_models = TRUE)

pred = rr$prediction()
pred$score(msrs(c("classif.auc", "classif.acc")))
as.data.table(pred)
```

这些预测来自训练集内部各折验证，不是测试集预测。

## 8. 嵌套重抽样

如果 learner 本身会调参或做特征选择，例如 `auto_tuner()`、`auto_fselector()`，外层仍需重抽样估计完整流程的泛化能力：

```r
outer_cv = rsmp("cv", folds = 3)
rr_nested = resample(train_task, at, outer_cv, store_models = TRUE)
rr_nested$aggregate(msr("classif.auc"))
```

内层 CV 用于选超参数，外层 CV 用于估计调参流程性能。不要混淆两者。

## 9. 并行提醒

重抽样和调参可并行，但必须先获得用户授权：

```r
parallel::detectCores()
# 询问用户后：
future::plan("multisession", workers = n)
```
