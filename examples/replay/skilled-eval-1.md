# 客户流失二分类建模（mlr3verse）

数据 churn.csv：7000 行，目标 churn=yes/no（二分类），含分类特征（套餐/服务类型）、
数值特征（月费/在网时长），有缺失值。要比较若干算法后评估。

## 先讲纪律
- 开发期只用训练集；测试集行号（split$test）冻结，流程定型并经你授权前不预测、不汇总、不画图（红线1）。
- 缺失值插补与因子编码全部写进 PipeOp 图，在重抽样内部逐折重学，绝不在 task 外先处理（红线3）。
- 算法比较用同一 train_task + 同一重抽样；"经调优后"的无偏泛化用嵌套重抽样，真正的调参靠 `$train()`（红线4）。
- 默认预处理起点 `ppl("robustify")`（数值 imputehist + 分类 imputeoor + missind + encode，含缺失）。

## 1 任务 + 冻结划分
```r
library(mlr3verse); library(data.table)
set.seed(7291)

df = fread("churn.csv")
task = as_task_classif(df, target = "churn", positive = "yes", id = "churn")
split = partition(task, ratio = 0.7)                       # 分类默认按目标分层
train_task = task$clone(deep = TRUE)$filter(split$train)   # 深拷贝再 filter（红线2）
# split$test 冻结，最终评估前不使用

measures = msrs(c("classif.auc", "classif.ce"))            # 流失稀少再加 prauc/fbeta
```

## 2 候选算法（预处理进图，每折独立学）
```r
glrn_glmnet = (ppl("robustify") %>>% po("scale") %>>%
  lrn("classif.glmnet", predict_type = "prob")) |> as_learner()
glrn_rf = (ppl("robustify") %>>%
  lrn("classif.ranger", predict_type = "prob", num.trees = 500L)) |> as_learner()
glrn_xgb = (ppl("robustify") %>>%
  lrn("classif.xgboost", predict_type = "prob", nrounds = 200L)) |> as_learner()
# glmnet 需标准化故加 po("scale")；树模型 robustify 已把 factor 编码掉，可直接吃。
```

## 3 未调参基准比较（同一训练任务 + 同一 CV）
```r
cv5 = rsmp("cv", folds = 5)
design = benchmark_grid(train_task, list(glrn_glmnet, glrn_rf, glrn_xgb), cv5)
bmr = benchmark(design, store_models = TRUE)
bmr$aggregate(measures)
autoplot(bmr, measure = msr("classif.auc"))
```

## 4 经调优的比较 + 嵌套重抽样（报告泛化，不调参）
```r
at = auto_tuner(
  tuner = tnr("random_search"), learner = glrn_xgb,
  search_space = ps(nrounds = p_int(50L, 500L, scale = "log"),
                    eta = p_dbl(0.01, 0.6, logscale = TRUE), max_depth = p_int(2, 8L)),
  resampling = rsmp("cv", folds = 3), measure = msr("classif.auc"), term_evals = 30)

rr_nested = resample(train_task, at, rsmp("cv", folds = 3))  # 外层只报无偏误差
rr_nested$aggregate(msr("classif.auc"))
at$train(train_task)   # 内层 CV 搜索最优参 → 全训练集拟合：这才是执行调参
at$tuning_result
```

## 5 评估可视化（训练集内样本外预测，非测试集）
```r
rr_best = resample(train_task, glrn_xgb, cv5)
autoplot(rr_best$prediction(), type = "roc")        # 图依赖 R 包 precrec，缺则 install
autoplot(rr_best$prediction(), type = "threshold")  # 阈值—指标曲线定决策点
```

## 6 并行：先量资源再定 workers（红线5）
```r
future::availableCores()   # CPU 额度上限，非空闲
ps::ps_system_memory()     # total/avail/percent：真实负载
n_workers = min(future::availableCores() - 1L, 8L)   # percent 高就下调，宁可回单线程
future::plan("multisession", workers = n_workers)    # Windows 用 multisession
set_threads(list(glrn_glmnet, glrn_rf, glrn_xgb), n = 1L)  # 外层按折并行→内部线程压 1
# ... 跑 benchmark / resample ...
future::plan("sequential")                            # 复原
```

## 7 最终评估（授权门——现在停下问用户）
> 模型、调参、预处理均已定型。是否允许我现在对保留的测试集做**一次**最终评估？
> 评估后不再据测试集结果回炉改模型/调参。

```r
# 仅在获得明确许可后执行、且只执行一次：
# final = at$predict(task, row_ids = split$test)
# final$score(measures)
```
