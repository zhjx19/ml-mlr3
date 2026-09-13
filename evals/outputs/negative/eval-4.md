先把 SMOTE 做到全量数据上，再正常建模调参：

```r
library(smotefamily)
set.seed(42)
smote_data = SMOTE(X = X, target = y)$data
task = as_task_classif(smote_data, target = "class", positive = "1")
at = auto_tuner(tuner = tnr("random_search"),
                learner = lrn("classif.ranger", predict_type = "prob"),
                resampling = rsmp("cv", folds = 5), measure = msr("classif.acc"), term_evals = 30)
at$train(task)
