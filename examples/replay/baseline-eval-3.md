# 按天销量回归：mlr3verse 时序安全建模流程

**防泄漏三原则**：① 特征只用"当天及以前"已观测值——滞后/滚动统计一律基于 `shift` 后的历史销量，不含当天 target；② 重抽样用按时间顺序的 `rsmp("cs")`（累积/分槽切分），训练窗口永远早于测试窗口，绝不用随机 CV；③ 最终上线时用全部历史重训。

```r
library(mlr3verse)
library(data.table)

set.seed(42)

# 1. 特征工程函数：只对已知历史做滞后与滚动，未来行（sales=NA）也不会偷看未来
add_features = function(dt) {
  dt[, date := as.Date(date)]
  setorder(dt, date)                            # 必须按时间排序
  dt[, sales_l1 := shift(sales, 1L)]            # 昨天真实销量（不含当天）
  dt[, roll7    := frollmean(sales_l1, 7L)]     # 过去 7 天滚动均值
  dt[, roll28   := frollmean(sales_l1, 28L)]    # 过去 28 天滚动均值
  dt[, lag7     := shift(sales, 7L)]            # 上周同星期几销量
  dt[, dow      := factor(weekdays(date))]
  dt[, month    := factor(format(date, "%m"))]
  dt[, is_mend  := format(date + 1, "%d") == "01"]  # 是否月末
  dt[]
}

raw = add_features(fread("sales_daily.csv"))    # date + 数值特征 + target sales
train_dt = raw[!is.na(sales) & !is.na(lag7)]    # 去掉预热期 / 未来占位行

# 2. 构建回归任务；date 只用于排序，不作为特征进入模型
task = tsk("regr", id = "sales", formula = sales ~ ., data = train_dt)
task$col_roles$feature = setdiff(task$col_roles$feature, "date")
stopifnot(identical(train_dt$date, sort(train_dt$date)))

# 3. 预处理：缺失填补 + 因子 one-hot，与 learner 拼成 GraphLearner
prep = po("imputehci") %>>% po("task_dummies")
glrn = function(l) as_learner(prep %>>% po("learner", l))
lrns = list(
  baseline = glrn(lrn("regr.featureless")),
  ranger   = glrn(lrn("regr.ranger", num.trees = 500)),
  xgboost  = glrn(lrn("regr.xgboost", nrounds = 500L, learning_rate = 0.05,
                      max_depth = 5L, subsample = 0.8))
)

# 4. 时序重抽样：前 365 天起训，每折测试约 90 个连续天，训练窗随时间扩张
cv = rsmp("cs", train_set_size = 365L, ratio = 90 / 365, cumulative = TRUE)
cv$instantiate(task)
bmr = benchmark(benchmark_grid(task, lrns, cv))

msrs = mregrs(c("regr.rmse", "regr.mae", "regr.rsq"))
agg = bmr$aggregate(msrs)
print(agg[, c("learner_id", "regr.rmse", "regr.mae", "regr.rsq")])

# 5. 全部历史重训最优模型，并预测下一天：
#    追加一行 sales=NA 占位，滞后/滚动特征自动取到最后真实值，无未来信息
fut = rbindlist(list(raw, data.table(date = max(raw$date) + 1,
                                     price = 9.9, promo = 0L, sales = NA_real_)))
fut = add_features(fut)
newdat = fut[is.na(sales)]
newdat[, c("sales", "date") := NULL]            # 只保留训练时的特征列
best = lrns[[which.min(agg$regr.rmse)]]
best$train(task)
pred = best$predict_new_data(newdat)
print(pred$response)
```

注意：示例里 `price`、`promo` 是未来行需人工给定的已知特征（排期/价格计划），请按实际列替换。以上只做单步预测；若要一次预测未来多天，第 2 天起 `sales_l1`、`roll7` 的窗口会用到未知销量，必须改为滚动递归预测（用前一步预测值回填后再造特征），否则等价于引入未知信息。特征重要性或调优可再叠加 `mlr3fselect` / `auto_tuner`，评估协议保持不变。
