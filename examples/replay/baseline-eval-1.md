# 客户流失预测：mlr3verse 完整建模流程

**流程**：读数据构建 `Task` → 先划出 20% holdout（最后评估前不碰）→ 预处理管道（补缺失 + one-hot + 标准化）→ 重复 5 折交叉验证比较多个算法 → 按指标选最优，在全量训练行上重训，最后在 holdout 上评估。

```r
library(mlr3verse)
library(data.table)

set.seed(42)

# 1. 读取数据，构建二分类任务（churn: yes/no）
dat = fread("churn.csv")                        # 7000 行
dat[, churn := as_factor(churn)]
task = tsk("classif", id = "churn", formula = churn ~ ., data = dat)

# 2. 预留 holdout：只保留到最后做无偏评估
split = rsmp("holdout", ratio = 0.8)            # 80% 训练 / 20% 测试
split$instantiate(task)
train_task = task$clone()$filter(split$train)
test_task  = task$clone()$filter(split$test)

# 3. 预处理管道：直方图/众数+常数填补并加缺失指示列，
#    套餐类型/服务类型等因子 one-hot，数值特征（月费、在网时长）稳健标准化
prep = po("imputehci") %>>%
       po("missind", affects = "numerics") %>>%
       po("task_dummies") %>>%
       po("scale", which = "numerics", robust = TRUE)

# 4. 待比较算法：基线 / 决策树 / 随机森林 / XGBoost，统一包进预处理图
glrn = function(l) as_learner(prep %>>% po("learner", l))
lrns = list(
  baseline = glrn(lrn("classif.featureless")),
  rpart    = glrn(lrn("classif.rpart", cp = 0.01, xval = 0)),
  ranger   = glrn(lrn("classif.ranger", num.trees = 500, respect.ui = TRUE)),
  xgboost  = glrn(lrn("classif.xgboost", nrounds = 400L, learning_rate = 0.05,
                      max_depth = 4L, subsample = 0.8, colsample_bytree = 0.8))
)

# 5. 重复 5 折 CV 基准比较（只在训练行上进行，holdout 不参与）
cv = rsmp("repeated_cv", folds = 5, repeats = 2)
cv$instantiate(train_task)
bmr = benchmark(benchmark_grid(train_task, lrns, cv))

msrs = msrs(c("classif.auc", "classif.logloss", "classif.acc", "classif.kappa"))
agg = bmr$aggregate(msrs)
print(agg[, c("learner_id", "classif.auc", "classif.logloss", "classif.acc")])

# 6. 选最优（logloss 越小越好），全量训练行重训后在 holdout 上最终评估
best = lrns[[which.min(agg$classif.logloss)]]
best$train(train_task)
pred = best$predict(test_task)
print(pred$score(msrs))

# 7. 业务视角检查：混淆矩阵看 yes/no 两类的召回是否有偏
confusionmatrix(pred)
```

说明几点：`imputehci` 对数值列用直方图/常数填补、因子列用众数，`missind` 生成的缺失指示列本身常含预测信号（如"月费缺失"可能对应新用户），建议保留；随机森林对缺失敏感，所以统一走填补管道而不是让某些 learner 裸奔。若后续要调参，可把 `benchmark` 换成 `auto_tuner`（`tnsn` 指定搜索域），评估协议不用改。
