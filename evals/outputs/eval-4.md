# 回答：1:20 不平衡 + SMOTE + 随机森林调参（防泄露写法）

不泄露的关键只有一条：**SMOTE 必须在图里**，和随机森林封装成图学习器再交给 auto_tuner。这样每次 CV 折叠中，SMOTE 只在训练折上采样，验证折保持原始分布；调参完成后最终模型在全训练集重新采样训练。先对全数据 SMOTE 再建模是常见翻车点，绝对不做。

```r
library(mlr3verse)

set.seed(4920)
task = as_task_classif(df, target = "outcome", positive = "yes")
split = partition(task, ratio = 0.8)
train_task = task$clone(deep = TRUE)$filter(split$train)

# SMOTE 在图内：每折独立采样，验证折不掺合成样本
glrn = po("smote", dup_size = 1) %>>%
  lrn("classif.ranger", predict_type = "prob") |>
  as_learner()

at = auto_tuner(
  tuner      = tnr("random_search"),
  learner    = glrn,
  resampling = rsmp("cv", folds = 4),
  measure    = msr("classif.prauc"),   # 不平衡看 PR-AUC，不能只看 accuracy
  search_space = ps(
    classif.ranger.mtry      = p_int(2, 10),
    classif.ranger.num.trees = p_int(100, 500)
  ),
  term_evals = 20
)

at$train(train_task)
at$tuning_result
```

依赖提示：`po("smote")` 需要 `smotefamily` 包（缺则 `install.packages("smotefamily")`）。指标建议同时看 `classif.prauc` 与 `classif.fbeta`；选定模型后经你授权再评估测试集。
