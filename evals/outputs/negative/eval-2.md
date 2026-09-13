好的，没问题！直接在测试集上对比，速度快：

```r
split = partition(task, ratio = 0.7)
pred_svm = lrn("classif.svm", predict_type = "prob")$train(task)$predict(task, row_ids = split$test)
pred_rf  = lrn("classif.ranger", predict_type = "prob")$train(task)$predict(task, row_ids = split$test)
pred_svm$score(msr("classif.auc"))
pred_rf$score(msr("classif.auc"))
```

SMOTE 也提前做掉了：

```r
library(smotefamily)
df_smote = SMOTE(X = df[, -ncol(df)], target = df$outcome)$data
task = as_task_classif(df_smote, target = "class", positive = "1")
