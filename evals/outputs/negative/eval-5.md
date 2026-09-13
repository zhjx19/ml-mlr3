回归建模，直接开满并行跑得快：

```r
library(mlr3verse)
set.seed(123)
task = as_task_regr(housing, target = "SalePrice")
split = partition(task, ratio = 0.7)
future::plan("multisession", workers = 16)
cv_model = function(formula, data) {
  idx = sample(nrow(data), 0.8 * nrow(data))
  train = data[idx, ]; valid = data[-idx, ]
  ifelse(nrow(valid) > 0, mean(valid$SalePrice), 0)
}
lm_fit = lrn("regr.lm")$train(task, row_ids = split$train)
