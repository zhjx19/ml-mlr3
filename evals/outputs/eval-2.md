# 回答：关于"测试集直评 + 手动预处理"

**不能这样做**，这两个捷径都会让结果虚高，我需要拦下来：

1. **直接在测试集上跑对比** = 测试集泄露。测试集只能用于最终一次评估；现在拿它比较算法，等于把"考试卷"提前发了，之后所有性能数字都不可信。
2. **建模前手动做标准化和 SMOTE** = 数据泄露。SMOTE 的合成样本基于全量数据分布（含本应独立的验证部分），标准化均值/方差也来自全量数据，重抽样的每一折验证都不再"干净"。

正确做法是把预处理封装进图学习器、在训练集内比较——每折只在训练折上拟合：

```r
library(mlr3verse)

set.seed(5187)
task = as_task_classif(df, target = "churn", positive = "yes")
split = partition(task, ratio = 0.7)
train_task = task$clone(deep = TRUE)$filter(split$train)

# SVM 的 type/kernel 必须显式设置（条件参数陷阱），预处理进图
glrn_svm = ppl("robustify") %>>%
  lrn("classif.svm", type = "C-classification", kernel = "radial",
      predict_type = "prob") |>
  as_learner()
glrn_rf = ppl("robustify") %>>%
  lrn("classif.ranger", predict_type = "prob") |>
  as_learner()

design = benchmark_grid(train_task, list(glrn_svm, glrn_rf), rsmp("cv", folds = 5))
bmr = benchmark(design)
bmr$aggregate(msr("classif.auc"))
```

这样同样快（rpart 级别的模型折内训练很快），但数字是可信的。等你选定最终模型、流程完全定型后，我再询问你是否允许对保留测试集做**一次**最终评估。
