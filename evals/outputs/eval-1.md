# 回答：客户流失二分类建模流程

好的。按规范流程走：先冻结训练/测试划分，开发期只用训练集，预处理全部封装进图学习器（防泄露），训练集内 CV 比较两个算法，最后经你授权才碰测试集。

```r
library(mlr3verse)
library(data.table)

set.seed(6314)
churn = fread("churn.csv")

# 1. 任务与数据花费：一次性划分，冻结 split
task = as_task_classif(churn, target = "churn", positive = "yes")
split = partition(task, ratio = 0.7)
train_task = task$clone(deep = TRUE)$filter(split$train)

measures = msrs(c("classif.auc", "classif.ce", "classif.prauc"))

# 2. 预处理（缺失值插补/编码等）封装进 ppl("robustify")，在重抽样内部拟合
glrn_glmnet = ppl("robustify") %>>%
  lrn("classif.glmnet", predict_type = "prob") |>
  as_learner()
glrn_ranger = ppl("robustify") %>>%
  lrn("classif.ranger", predict_type = "prob") |>
  as_learner()

# 3. 并行：先量可用资源再定 workers（availableCores() 只报上限，不代表机器空闲）
cores = future::availableCores()
mem = ps::ps_system_memory()          # percent 高就说明机器在忙，下调 workers
set_threads(list(glrn_glmnet, glrn_ranger), n = 1L)  # 外层按折并行 → 内部线程压成 1
future::plan("multisession", workers = min(cores - 1L, 8L))

# 4. 训练集内 benchmark 比较两个算法
design = benchmark_grid(
  tasks = train_task,
  learners = list(glrn_glmnet, glrn_ranger),
  resamplings = rsmp("cv", folds = 5)
)
bmr = benchmark(design, store_models = TRUE)
bmr$aggregate(measures)

# 5. 评估可视化
autoplot(bmr, measure = msr("classif.auc"))
```

跑完记得 `future::plan("sequential")` 复原。两点说明：

- 并行不需要事先征求同意，但 workers 由探测到的资源决定：`availableCores()` 给的是额度上限，内存负载看 `ps_system_memory()`；机器忙（或你同时在跑别的东西）就往下调，必要时退回单线程。外层按折并行时 learner 内部线程必须压成 1，否则 N 个 worker 各开满核互相争抢。
- 模型比较与定型全部完成后，我会先询问你是否允许对保留测试集做一次最终评估；在那之前不会对它做任何预测、汇总或可视化。
