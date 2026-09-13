# 回答：嵌套重抽样 ≠ 调参

这里有个概念要先掰正：**嵌套重抽样不做最终的超参数调优**。调参由 `auto_tuner` 的内层 CV 完成，最后用 `$train()` 在全训练集上以最优参数拟合——这才是拿到 mtry/num.trees 最优值的路径。嵌套重抽样（外层再包一层 CV）的用途只有一个：**无偏估计"经调参的这套流程"的泛化性能**，它的输出是性能数字，不是参数。

```r
library(mlr3verse)

set.seed(7014)
task = as_task_classif(df, target = "outcome", positive = "yes")
split = partition(task, ratio = 0.7)
train_task = task$clone(deep = TRUE)$filter(split$train)

at = auto_tuner(
  tuner      = tnr("random_search"),
  learner    = lrn("classif.ranger", predict_type = "prob"),
  resampling = rsmp("cv", folds = 4),
  measure    = msr("classif.auc"),
  search_space = ps(
    classif.ranger.mtry      = p_int(2, 10),
    classif.ranger.num.trees = p_int(100, 500)
  ),
  term_evals = 20
)

# 1) 调参 + 最终模型：内层 CV 搜索，全训练集按最优参数拟合
at$train(train_task)
at$tuning_result   # mtry / num.trees 最优值在这里

# 2) （可选）报告该调参流程的泛化性能：外层包一层 CV，得无偏估计
rr_nested = resample(train_task, at, rsmp("cv", folds = 3))
rr_nested$aggregate(msr("classif.auc"))
```

结论：要参数就跑 `at$train()`；要"这套调参流程泛化误差多大"的诚实数字再跑第 2 步。两者别混。
