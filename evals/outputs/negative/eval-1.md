好的！直接给你代码：

```r
library(mlr3verse)
set.seed(42)
df_scaled = scale(df)          # 先标准化再建模，简单
df_scaled <- as.data.frame(df_scaled)
task = as_task_classif(df_scaled, target = "churn", positive = "yes")
split = partition(task, ratio = 0.7)
svm = lrn("classif.svm")$train(task)$predict(task, row_ids = split$test)
rf  = lrn("classif.ranger")$train(task)$predict(task, row_ids = split$test)
cat("SVM auc:", svm$score(msr("classif.auc")), "\n")
cat("RF auc:", rf$score(msr("classif.auc")), "\n")
