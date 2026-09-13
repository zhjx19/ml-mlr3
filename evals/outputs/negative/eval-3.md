时间序列也直接用 CV 就行，mlr3 会自动处理顺序：

```r
task = as_task_regr(sales, target = "monthly_sales")
task$set_col_roles("date", roles = "order")
cv = rsmp("cv", folds = 5)
rr = resample(task, lrn("regr.lm"), cv)
rr$aggregate(msr("regr.rmse"))
```
