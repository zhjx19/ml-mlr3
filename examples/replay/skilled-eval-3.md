# 按天销量回归（mlr3verse）——时序禁止随机划分

数据：date 列 + 数值特征 + target sales（回归），要求训练不得使用未来数据。

## 关键纪律（时序专属）
- 时序**禁用** `partition()` 与随机 `rsmp("cv")`——它们会把未来撒进训练集；`order` 角色
  只作时间标记，**不改变**随机重抽样的切分方式（实测 holdout 测试集行号散布在中段）。
- 按时间位置显式切：前段训练、后段留最终评估，训练窗严格早于验证窗。
- 开发期用 `rsmp("custom")` 手写滚动折（内置字典**无** rolling_origin）。
- 缺失/编码进图；比较用同一滚动折；嵌套重抽样只报无偏泛化；并行先量资源；测试集授权后评估。

## 1 任务（务必先按时间升序，行号与时间同序）
```r
library(mlr3verse); library(data.table)
set.seed(5149)

df = fread("sales.csv")
df = df[order(date)]                          # row_ids 必须随时间单调，供下方切片
task = as_task_regr(df, target = "sales", id = "sales")
task$set_col_roles("date", roles = "order")   # 仅标记，不替代显式切分
```

## 2 冻结式时间划分
```r
n = task$nrow
train_ids = seq_len(floor(n * 0.8))           # 前 80% 时间段训练
test_ids  = seq(floor(n * 0.8) + 1L, n)       # 后 20% 仅最终评估，冻结
train_task = task$clone(deep = TRUE)$filter(train_ids)  # 深拷贝再 filter（红线2）

measures = msrs(c("regr.rmse", "regr.mae", "regr.rsq"))
```

## 3 滚动折（训练窗严格早于验证窗；验证窗长 = 业务预测 horizon）
```r
n_tr = train_task$nrow
b1 = floor(n_tr * 0.55); b2 = floor(n_tr * 0.70); b3 = floor(n_tr * 0.85)
rc = rsmp("custom")
rc$instantiate(train_task,
  train = list(seq_len(b1),            seq_len(b2),            seq_len(b3)),
  test  = list((b1 + 1L):b2, (b2 + 1L):b3, (b3 + 1L):n_tr))
```

## 4 候选算法（预处理进图，每折重学；lag/日历特征也必须是图内 PipeOp）
```r
glrn_rf = (ppl("robustify") %>>% lrn("regr.ranger", num.trees = 500L)) |> as_learner()
glrn_glmnet = (ppl("robustify") %>>% po("scale") %>>% lrn("regr.glmnet")) |> as_learner()
glrn_xgb = (ppl("robustify") %>>% lrn("regr.xgboost", nrounds = 200L)) |> as_learner()
```

## 5 基准比较 + 嵌套重抽样 + 最终拟合
```r
design = benchmark_grid(train_task, list(glrn_rf, glrn_glmnet, glrn_xgb), rc)  # 同一滚动折
bmr = benchmark(design, store_models = TRUE)
bmr$aggregate(measures)
autoplot(bmr, measure = msr("regr.rmse"))

at = auto_tuner(
  tuner = tnr("random_search"), learner = glrn_xgb,
  search_space = ps(nrounds = p_int(50L, 500L, scale = "log"),
                    eta = p_dbl(0.01, 0.6, logscale = TRUE), max_depth = p_int(2, 8L)),
  resampling = rc$clone(deep = TRUE), measure = msr("regr.rmse"), term_evals = 30)
rr_nested = resample(train_task, at, rc$clone(deep = TRUE))  # 外层只报无偏 RMSE
rr_nested$aggregate(msr("regr.rmse"))
at$train(train_task)   # 内层滚动折搜索 → 全训练时段拟合：真正执行调参
```

## 6 可视化（滚动折验证预测，非测试集）
```r
pred_dt = as.data.table(rr_nested$prediction())  # obs vs pred 散点 + 残差图
# 完整 ggplot 写法见 references/evaluation.md
```

## 7 并行（外层按折并行时把 learner 内部线程压 1）
```r
future::availableCores(); ps::ps_system_memory()
future::plan("multisession", workers = min(future::availableCores() - 1L, 8L))
set_threads(list(glrn_rf, glrn_glmnet, glrn_xgb), n = 1L)   # 形参是 n，勿写 nthreads
# ... 跑 benchmark / resample ...
future::plan("sequential")
```

## 8 最终评估（授权门）
> 前 80% 时段训练的模型已定型。是否允许我仅对后 20% 时段做**一次**最终评估？
> 时序评估后不得据结果回炉改模型——那会污染未来信息。

```r
# 获许可后、只此一次：
# at$predict(task, row_ids = test_ids)$score(measures)
```
