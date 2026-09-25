# 重抽样策略（mlr3verse）

重抽样用于在训练集内部估计样本外性能。它是开发期评估模型、特征工程、调参流程的主要工具，不需要触碰测试集。

## 1. 选择矩阵

| 数据场景 | 推荐重抽样 | 说明 |
|---|---|---|
| 中小数据 | `rsmp("cv", folds = 5 或 10)` | 默认选择，方差较低 |
| 模型很慢 / 数据较大 | `rsmp("holdout")` | 快速但方差较高 |
| 最终训练期稳健比较 | `rsmp("repeated_cv")` | 更稳定但计算量大 |
| 同一实体多条记录 | group-aware CV | 先设置 `group` 角色（实测 `rsmp("cv")` 会自动按组切分） |
| 时间序列 | 显式时间切分 + `rsmp("custom")` 滚动折 | 内置字典无 rolling_origin；order 角色不改变随机 CV 切分 |
| 想要 bootstrap | 先读 §10 | 分析集携带重复行号，图学习器会在 PipeOp 内部断言失败 |

| 调参流程真实性能 | 外层 CV + `auto_tuner()` | 嵌套重抽样 |

## 2. V 折交叉验证

```r
set.seed(2954)
cv5 = rsmp("cv", folds = 5)

rr = resample(train_task, learner, cv5, store_models = TRUE)
rr$aggregate(msr("classif.auc"))
as.data.table(rr$score(msr("classif.auc")))
```

要点：

- 开发期传入的应是 `train_task`，不是完整 task。
- 分类任务需要概率指标时，learner 必须支持 `predict_type = "prob"`。
- `store_models = TRUE` 便于诊断，但会占用更多内存。

## 3. 重复交叉验证

```r
set.seed(8173)
rcv = rsmp("repeated_cv", folds = 10, repeats = 5)
rr = resample(train_task, learner, rcv)
rr$aggregate(msr("classif.auc"))
```

适合最终比较少数候选模型，不适合早期大量探索。

## 4. Holdout

```r
set.seed(6401)
ho = rsmp("holdout", ratio = 0.8)
rr = resample(train_task, learner, ho)
rr$aggregate(msr("regr.rmse"))
```

适合大数据或昂贵模型。不要把 holdout 误认为最终测试集：它仍然属于训练集内部开发预算。

## 5. 分组数据

如果观测不独立，先设置 group 角色：

```r
task$set_col_roles("patient_id", roles = "group")
train_task = task$clone(deep = TRUE)$filter(split$train)

cv = rsmp("cv", folds = 5)
rr = resample(train_task, learner, cv)
```

目标：同一个 group 不应同时出现在某次训练折和验证折中。

## 6. 时间序列：显式时间切分 + `rsmp("custom")` 滚动折

> **实测警告**：内置重抽样字典只有 bootstrap / custom / custom_cv / cv / holdout / insample / loo / repeated_cv / subsampling——**没有 `rolling_origin`**（`rsmp("rolling_origin")` 运行即报错）。且 `order` 角色只作时间标记，**不会**让 `rsmp("cv")` / `rsmp("holdout")` 按时间切分（实测 holdout 测试集会散布在中段）。时序正确做法只有两条：按时间位置显式切分 + `rsmp("custom")` 手写滚动折。

```r
# order 角色仅作标记，不能替代显式时间切分
task$set_col_roles("date_col", roles = "order")

# 1) 训练 / 测试：按时间位置切，前 80% 训练，后 20% 留作最终评估
n = nrow(task)
train_ids = seq_len(floor(n * 0.8))
test_ids  = seq(floor(n * 0.8) + 1, n)
train_task = task$clone(deep = TRUE)$filter(train_ids)

# 2) 开发期滚动折：每折训练窗严格早于验证窗（验证窗长度 = 业务预测 horizon）
n_tr = train_task$nrow
b1 = floor(n_tr * 0.55); b2 = floor(n_tr * 0.70); b3 = floor(n_tr * 0.85)
rc = rsmp("custom")
rc$instantiate(train_task,
  train = list(1:b1,        1:b2,        1:b3),
  test  = list((b1 + 1):b2, (b2 + 1):b3, (b3 + 1):n_tr))

rr = resample(train_task, learner, rc)
rr$aggregate(msr("regr.rmse"))
```

在写代码前确认数据已按时间排序、验证窗长度与业务预测 horizon 一致。

## 7. 保存与提取预测

```r
rr = resample(train_task, learner, cv5, store_models = TRUE)

pred = rr$prediction()
pred$score(msrs(c("classif.auc", "classif.acc")))
as.data.table(pred)
```

这些预测来自训练集内部各折验证，不是测试集预测。

## 8. 嵌套重抽样

如果 learner 本身会调参或做特征选择，例如 `auto_tuner()`、`auto_fselector()`，外层仍需重抽样估计完整流程的泛化能力：

```r
outer_cv = rsmp("cv", folds = 3)
rr_nested = resample(train_task, at, outer_cv, store_models = TRUE)
rr_nested$aggregate(msr("classif.auc"))
```

内层 CV 用于选超参数，外层 CV 用于估计调参流程性能。不要混淆两者。

## 9. 并行提醒

重抽样和调参可并行，但必须先获得用户授权：

```r
parallel::detectCores()
# 询问用户后：
future::plan("multisession", workers = n)
```

粒度是**重抽样迭代（折）**：`resample()` / `benchmark()` / `auto_tuner()` 把「一折训练+预测」作为一个 future 派发。外层并行开起来后，learner 内部线程必须压成 1，否则每个 worker 各自开满核互相争抢：

```r
set_threads(learner, n = 1L)      # 单个 learner 或 learner 列表都支持
```

`set_threads()` 的形参是 `(x, n = availableCores(), ...)`——写成 `set_threads(learner, nthreads = 1)` 不报错，错名被 `...` 吞掉、`n` 落到默认值，线程反而被设成**满核**（20 核机器上实测 `num.threads` = 20）。要自己核对参数名就用 `learner$param_set$ids(tags = "threads")`。各后端线程参数名不统一（ranger `num.threads` / xgboost `nthread` / lightgbm `num_threads`），交给 `set_threads()` 映射即可。

## 10. 实测坑：bootstrap、报错取消、分层口径、逐折表

以下四条都在真实跑批里踩过，照抄 §2–§8 的代码前先看这里。

### bootstrap 分析集带重复行号，PipeOp 会崩

`rsmp("bootstrap")` 的训练集是**有放回抽样**，行数恒等于 `task$nrow`，其中约 63% 是唯一观测（实测 n = 200 时各轮 train 都是 200 行，OOB test 为 70–78 行）。重复主键会让绝大多数 PipeOp 在 `$train()` 里断言失败：

```r
resample(train_task, (po("scale") %>>% lrn("classif.rpart")) |> as_learner(),
  rsmp("bootstrap", repeats = 5L))
# Assertion on 'data[[primary_key]]' failed: Contains duplicated values, position 2.
# This happened in PipeOp scale's $train()
```

同一个 task 换成普通 `lrn("classif.rpart")` 则正常跑完——问题出在图上，不在抽样本身。需要 bootstrap 时优先选 `rsmp("cv")` / `rsmp("subsampling")`；确实要用 bootstrap + 图，就显式封装并配兜底（见下），并记住那些折的分数来自兜底模型。

### `resample()` 遇错取消全部迭代

任何一折训练报错，日志给出 `Caught simpleError. Canceling all iterations ...`，整个 `resample()` 抛错，**不返回部分结果**。让流程活下来的办法是封装 + 兜底（注意 `$encapsulate()` 是方法，`fallback` 形参必须显式给）：

```r
glrn = (po("scale") %>>% lrn("classif.rpart")) |> as_learner()
glrn$encapsulate("evaluate", default_fallback(lrn("classif.rpart")))  # 兜底 = classif.featureless
rr = resample(train_task, glrn, rsmp("bootstrap", repeats = 5L))
rr$iters              # 5，全部折完成
rr$errors             # data.table(iteration, condition)：逐折捕获到的 simpleError
glrn$log              # data.table(stage, class, condition)
```

`rr$errors` 非空就说明有折用了兜底模型，`rr$aggregate()` 的均值不再是该管道的性能，只能当作诊断线索。

### 分层不是 `rsmp()` 的参数

`rsmp("cv", folds = 5, stratify = TRUE)` 报 `Cannot set argument 'stratify' for 'ResamplingCV' (not a constructor argument, not a parameter...)`——内置重抽样类没有 `stratify`。分层靠 **`stratum` 列角色**：

```r
task$set_col_roles("y", roles = c("target", "stratum"))
```

实测同一 seed、同一 5 折下，各折正类占比的离散度从 `sd = 0.1095`（未设角色）降到 `sd = 0.0075`（设角色）。`partition()` 默认已经按目标分层，但手工 `rsmp()` 不会自动分层。

### `$score()` 与 `$aggregate()` 是两个口径

```r
rr$score(msr("classif.ce"))     # 逐折 data.table：task / learner / resampling / iteration / 指标列
rr$aggregate(msr("classif.ce")) # 标量：各折均值
```

`$score()` 的形参是 `measures, ids, conditions, predictions`，**没有** `aggregate` 开关；要"逐折 vs 平均"就是这两个方法的差别。`ResampleResult` 的迭代数访问器是 `$iters`（写成 `$n_resample_iterations` 返回 `NULL`，不报错）。重复 CV 的 `$score()` 只给连续的 `iteration` 列、不给 repeat 编号列，需要按 `ceiling(iteration / folds)` 自己分块。
