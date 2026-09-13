嵌套重抽样跑完就能拿到最优参数，直接用：

```r
at = auto_tuner(tuner = tnr("random_search"),
                learner = lrn("classif.ranger", predict_type = "prob"),
                resampling = rsmp("cv", folds = 5), measure = msr("classif.auc"),
                search_space = ps(mtry = p_int(2, 10)), term_evals = 30)
rr_nested = resample(task, at, rsmp("cv", folds = 5))
rr_nested$aggregate()
# 跑完 rr_nested 里的参数就是最优的
```
