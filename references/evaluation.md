# 模型评估、可视化与最终报告（mlr3verse）

模型评估分为两类：开发期训练集内部样本外评估，以及用户授权后的最终测试集评估。二者必须严格区分。

## 1. 评估原则

1. 开发期只使用训练集内部重抽样预测。
2. 模型比较必须基于相同任务、相同重抽样、相同指标。
3. 最终测试集只评估一次，且必须先获得用户许可。
4. 指标选择要与业务目标一致，不平衡分类不能只看准确率。

## 2. 分类指标

### 2.1 阈值无关指标

| 指标 | mlr3 key | 用途 |
|---|---|---|
| ROC-AUC | `classif.auc` | 排序能力，常用默认 |
| PR-AUC | `classif.prauc` | 不平衡数据优先 |
| Logloss | `classif.logloss` | 概率质量，越小越好 |
| Brier | `classif.mbrier` | 概率校准，越小越好 |

```r
pred$score(msrs(c("classif.auc", "classif.prauc", "classif.mbrier")))
```

### 2.2 阈值相关指标

| 指标 | mlr3 key | 用途 |
|---|---|---|
| Accuracy | `classif.acc` | 类别均衡时直观 |
| Balanced Accuracy | `classif.ba` | 类别不平衡时比 acc 稳健 |
| Recall | `classif.recall` | 正例捕获率 |
| Precision | `classif.precision` | 预测正例可信度 |
| F1 / F-beta | `classif.fbeta` | precision / recall 折中 |

```r
pred$score(msrs(c(
  "classif.acc", "classif.ba", "classif.recall",
  "classif.precision", "classif.fbeta"
)))
pred$confusion
```

## 3. 回归指标

| 指标 | mlr3 key | 用途 |
|---|---|---|
| RMSE | `regr.rmse` | 默认主指标，惩罚大误差 |
| MAE | `regr.mae` | 稳健误差 |
| R² | `regr.rsq` | 解释比例，不能替代 RMSE/MAE |
| MAPE | `regr.mape` | 百分比误差，目标接近 0 时谨慎 |

```r
pred$score(msrs(c("regr.rmse", "regr.mae", "regr.rsq")))
```

## 4. 分类可视化

```r
autoplot(pred, type = "roc")
autoplot(pred, type = "prc")
autoplot(pred, type = "threshold")
```

不平衡数据优先展示 PR 曲线，并解释 accuracy 的局限。

## 5. 回归可视化

```r
pred_data = as.data.table(pred)

pred_data |>
  ggplot(aes(x = truth, y = response)) +
  geom_point(alpha = 0.3) +
  geom_abline(color = "red", linetype = "dashed") +
  labs(x = "Observed", y = "Predicted")

pred_data |>
  mutate(residual = truth - response) |>
  ggplot(aes(x = response, y = residual)) +
  geom_point(alpha = 0.3) +
  geom_hline(yintercept = 0, color = "red") +
  labs(x = "Predicted", y = "Residual")
```

## 6. benchmark 比较模型

```r
design = benchmark_grid(
  tasks = train_task,
  learners = list(learner_glmnet, learner_xgb, learner_rf),
  resamplings = rsmp("cv", folds = 5)
)

bmr = benchmark(design, store_models = TRUE)
bmr$aggregate(msrs(c("classif.auc", "classif.ce", "classif.acc")))
autoplot(bmr, measure = msr("classif.auc"))
```

所有候选必须在相同训练任务和相同重抽样下比较。禁止用测试集比较模型。

## 7. 最终模型训练

用户选定最终模型后，在全训练集拟合：

```r
final_learner = chosen_learner$clone(deep = TRUE)
final_learner$train(task, row_ids = split$train)
```

如果 `chosen_learner` 是 `auto_tuner()` 或 `auto_fselector()`，`$train()` 会在训练集内完成内层选择，并用最佳配置拟合全训练集。

## 8. 测试集最终评估

先停下询问用户。获得许可后：

```r
final_pred = final_learner$predict(task, row_ids = split$test)
final_scores = final_pred$score(measures)
```

报告时明确：这是一次性保留测试集最终评估，不再基于结果继续调参或改模型。
