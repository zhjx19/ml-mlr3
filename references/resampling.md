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

## 9. 并行：按机器配置自动定档

重抽样和调参可以自动并行，不必征求授权；要防两个坑——**凭空假设机器空闲**，以及它的反面：**mlr3 的学习器构造时一律是 1 线程**。不探测、不定档，跑的就是单核档。

### 9.1 先量三个数 + 一个并行单位数

```r
cores = future::availableCores()                  # 额度上限，不是当前空闲（本机实测恒为 20，即使机器正忙）
phys  = parallel::detectCores(logical = FALSE)    # 物理核（本机 20 逻辑 / 14 物理；NA 时退回 cores）
mem   = ps::ps_system_memory()                    # total / avail / percent（实测 percent 56.9）
rsmp$instantiate(train_task); n_unit = rsmp$iters  # 并行单位 = 折数
```

`percent` 才是真实负载信号：`availableCores()` 报的是额度，不是"现在有空"。两个探测的坑：`future` **没有** `availableMemory()`（只有 `availableCores` / `availableWorkers`），`memory.limit()` 已不再支持（实测只告警并返回 `Inf`）——都不能当负载用；没装 `ps` 就直接保守取档，别为了探测硬装包。

### 9.2 并行单位是折，不是候选

`resample()` / `benchmark()` / `auto_tuner()` 内部都是 `future_map()` 按**一个重抽样迭代**派发任务（`mlr3:::future_map`，默认 `mlr3.exec_chunk_size = 1`，一折一个 future）。`benchmark()` 会把设计表展开成「任务 × 学习器 × 折 × 参数组合」的逐行单元，所以它的并行单位数要乘学习器数。

推论三条：

- 内层 `rsmp("holdout")` 只有 1 折：**没有可分的任务**。开 future 只让每次评估都把 `Task` 序列化进 worker——本书记载的房价案例里，20 个候选从 **41.4 s 变成 10.1 s**（关掉 future 后）。这是"开了并行反而慢 4 倍"的典型。
- 内层 `rsmp("cv", folds = 5)`：5 折就是 5 个任务，**worker 给 5 个就够**，多给的不会更快。
- `auto_tuner()` 的候选数**不是**并行单位：`term_evals = 20` 仍然是 20 次串行评估，每次内部按折并行。

### 9.3 先看拟合耗时，再看折数

并行不改变结果、只改速度；**决定收益的是单次拟合耗时**（20 逻辑核 / 14 物理核，本书案例实测）：

| 单次拟合 | 实例 | 结论 |
|---|---|---|
| ≲ 0.1 s | rpart 1.6→3.4 s、nnet 1.6→3.2 s、小数据 ranger 1.5→4.0 s | **别开 future**，Task 序列化开销更大 |
| 0.1–0.5 s | XGBoost 21k 8.3 vs 8.4 s、LightGBM 2.9k 12.1 vs 12.2 s | 中性，开不开都行 |
| ≳ 1 s | ranger 图 26.2→12.8 s、CatBoost 图 275.1→118.8 s、特征选择 14.6→10.0 s | 开，1.5–2.3 倍 |

量一次拟合耗时：`learner$train(train_task); learner$state$train_time`（秒）。

| 并行单位数 | future | 学习器线程 | 依据 |
|---|---|---|---|
| `n_unit == 1`（holdout / 单次拟合） | **不开**，保持 `sequential` | 默认 1；`fit_secs >= 1` 才 `set_threads(n = phys - 1L)` | 没有可分任务；短拟合加线程反而慢 |
| `n_unit >= 2`（CV / subsampling / repeats） | `plan("multisession", workers = min(n_unit, cores - 1L, 内存档))` | 默认 1；仅当 `fit_secs >= 1` 且 `workers < phys` 时 `n = phys %/% workers` | 超过折数的 worker 不更快；workers × 线程 ≤ 物理核 |
| benchmark 多学习器 | 同上，`n_unit` 取**总单元数**（学习器 × 任务 × 折） | 同上 | 每个 future 是一个 (任务, 学习器, 折) 单元 |

内存档：每个 worker 各持一份 task 副本，`floor(mem$avail * 0.5 / as.numeric(object.size(train_task)))`。压到 1 就回单进程，线程按 `phys - 1` 给，并在输出里写清原因。

```r
plan_parallel = \(iters, fit_secs = NA_real_, cores = future::availableCores(),
  phys = parallel::detectCores(logical = FALSE), mem = NULL, task_bytes = 0) {
  phys = if (is.na(phys)) cores else min(phys, cores)
  mem_cap = if (!is.null(mem) && task_bytes > 0)
    max(1L, floor(mem$avail * 0.5 / task_bytes)) else Inf
  slow = isTRUE(fit_secs >= 1)                      # 单次拟合 ≥1 s 才考虑加线程
  if (iters <= 1L) {
    return(list(workers = 1L, mode = "sequential",
      thread = if (slow) as.integer(max(1L, phys - 1L)) else 1L))
  }
  w = as.integer(max(1L, min(iters, cores - 1L, mem_cap)))
  th = if (!slow) 1L else if (w == 1L) as.integer(max(1L, phys - 1L)) else
    as.integer(max(1L, phys %/% w))
  # 每折 1 线程时用 fork（Linux/macOS）省掉序列化；要给多线程就退回 multisession
  mode = if (w <= 1L) "sequential" else if (th == 1L && fork_ok) "multicore" else "multisession"
  list(workers = w, thread = th, mode = mode)
}

p = plan_parallel(rsmp$iters, fit_secs = learner$state$train_time,
                  mem = ps::ps_system_memory(),
                  task_bytes = as.numeric(object.size(train_task)))
if (p$mode == "sequential") {
  future::plan("sequential")        # 单进程档：线程按 p$thread 定
} else {
  future::plan(p$mode, workers = p$workers)
}
set_threads(learner, n = p$thread)
# ... resample() / benchmark() / auto_tuner() ...
future::plan("sequential")     # 跑完复原，别把档位留给后面的代码
```

`set_threads()` 对没有线程参数的学习器（rpart / lm 等）是空操作，同一个规划器可以无脑套在所有学习器上；GraphLearner 会把线程数传到图内每个学习器。

### 9.5 Windows 与 Linux 的后端不同

- **Windows**：只有 `multisession`（多进程）；`multicore` 不可用（`future::supportsMulticore()` 为 `FALSE`）。
- **Linux**：`multicore`（fork）可用，Task 不序列化、启动开销更低；macOS 也能 fork，但保守起见用 `multisession`。
- **实测**（4 核 ubuntu runner，3 worker；`scripts/bench_parallel_linux.R`）：

| 案例 | 串行 | multisession | multicore |
|---|---|---|---|
| 短拟合 rpart，5 折 × 10 次 | **1.31 s** | 3.30 s | 2.07 s |
| 长拟合 ranger 图，5 折 × 6 次 | 16.49 s | **10.98 s** | 11.74 s |

- 结论：multicore 的并行开销约为 multisession 的 **1/3**（短拟合多花 0.8 s vs 2.0 s），但**短拟合仍不如串行**；长拟合两者相当。所以——**每折 1 线程且 `supportsMulticore()` 为真 → `multicore`；要给每折多线程 → `multisession`**（fork 与 OpenMP 原生线程混用有死锁风险，fork 也不能嵌套）。
- `supportsMulticore()` 已经包含 RStudio / `parallelly.fork.enable` 的判断，直接调它，别自己写平台判断。

### 9.4 线程给几个：按学习器实测

| 学习器 / 数据 | 1 线程 | 4 线程 | 13 线程 | 结论 |
|---|---|---|---|---|
| LightGBM 2.9k×82 | **0.18 s** | 0.54 s | 1.70 s | 加线程慢 9.4 倍 |
| XGBoost 21k×18 | **0.22 s** | 0.21 s | 0.30 s | 1~4 无差 |
| XGBoost 105k×30 | 3.52 s | **2.21 s** | 2.94 s | 4 线程 1.6 倍 |
| CatBoost 20k×14 | 3.87 s | **3.12 s** | 3.23 s | 4 线程 1.24 倍 |
| ranger 20k×14（300 树） | 3.17 s | 1.24 s | **0.85 s** | 线程敏感（3.7 倍） |

**mlr3 与裸库的默认值不同**：

| 学习器 | 线程参数 | mlr3 学习器默认 | 裸库默认 |
|---|---|---|---|
| XGBoost | `nthread` | **1** | `NULL`（全核） |
| LightGBM | `num_threads` | **1** | `0`（全核） |
| CatBoost | `thread_count` | **1** | `1` |
| ranger | `num.threads` | **1** | 全核 |

现场探（前两个随 mlr3verse 就位，后两个要 `mlr3extralearners`）：`lrn("classif.xgboost")$param_set$values$nthread`、`lrn("classif.ranger")$param_set$values$num.threads`，以及 `regr.lightgbm` 的 `num_threads`、`regr.catboost` 的 `thread_count`——实测都是 `1`。所以既不能"以为不写就是全核"，也不能"以为压成 1 更稳"：**按 §9.3 的拟合耗时定档，总线程 ≤ 物理核**。

`set_threads()` 的形参是 `(x, n = availableCores(), ...)`——写成 `set_threads(learner, nthreads = 1)` 不报错，错名被 `...` 吞掉、`n` 落到默认值，线程反而被设成**满核**（20 核机器实测 `num.threads` = 20）。线程参数名不确定就现探 `learner$param_set$ids(tags = "threads")`，映射交给 `set_threads()` 做。

### 9.6 另一个后端：mirai

mlr3 1.8.0 的 `future_map()` 开头会先看 `mirai`：**只要 `mirai` 已加载且 daemons 已设**，就走 mirai，`future::plan()` 完全不生效（`getOption("mlr3.mirai_parallelization", "mlr3_parallelization")` 指定 daemons 名）。所以"我明明 plan 了 5 个 worker 怎么没变快"先查这一条：

```r
if (isNamespaceLoaded("mirai") && mirai::daemons_set()) {
  # mlr3 走的是 mirai，不是 future：要么关掉 daemons，要么按 mirai 的档位配
}
```

默认路线仍是 future；两条别同时开。

## 10. 实测坑：bootstrap、报错取消、分层口径、逐折表

以下四条都在真实跑批里踩过，照抄 §2–§8 的代码前先看这里。

### bootstrap 分析集带重复行号，PipeOp 会崩

`rsmp("bootstrap")` 的训练集是**有放回抽样**，行号会重复。重复主键让绝大多数 PipeOp 在 `$train()` 里断言失败：

```r
resample(train_task, (po("scale") %>>% lrn("classif.rpart")) |> as_learner(),
  rsmp("bootstrap", repeats = 5L))
# Assertion on 'data[[primary_key]]' failed: Contains duplicated values, position 2.
# This happened in PipeOp scale's $train()
```

同一个 task 换成普通 `lrn("classif.rpart")` 则正常跑完——问题出在图上，不在抽样本身。需要 bootstrap 时优先改用 `rsmp("cv")` / `rsmp("subsampling")`；确实要用 bootstrap + 图就显式封装并配兜底（见下），并记住那些折的分数来自兜底模型。

### `resample()` 遇错取消全部迭代

任何一折训练报错，日志给出 `Caught simpleError. Canceling all iterations ...`，整个 `resample()` 抛错，**不返回部分结果**。让流程活下来的办法是封装 + 兜底（`$encapsulate()` 是方法，`fallback` 形参必须显式给）：

```r
glrn = (po("scale") %>>% lrn("classif.rpart")) |> as_learner()
glrn$encapsulate("evaluate", default_fallback(lrn("classif.rpart")))  # 兜底 = classif.featureless
rr = resample(train_task, glrn, rsmp("bootstrap", repeats = 5L))
rr$iters      # 5，全部折完成
rr$errors     # 逐折捕获到的错误；非空 = 有折用了兜底模型
```

`rr$errors` 非空时，`rr$aggregate()` 的均值不再是该管道的性能，只能当诊断线索。

### 分层不是 `rsmp()` 的参数

`rsmp("cv", folds = 5, stratify = TRUE)` 报 `Cannot set argument 'stratify' for 'ResamplingCV' (not a constructor argument, not a parameter...)`——内置重抽样类没有 `stratify`。分层靠 **`stratum` 列角色**：

```r
task$set_col_roles("y", roles = c("target", "stratum"))
```

实测同一 seed、同一 5 折下，各折正类占比的离散度从 `sd = 0.1095`（未设角色）降到 `sd = 0.0075`（设角色）。`partition()` 默认按目标分层，手工 `rsmp()` 不会——这是两条不同的路径，别指望 `rsmp()` 自动分层。

### `$score()` 与 `$aggregate()` 是两个口径

```r
rr$score(msr("classif.ce"))     # 每折一行
rr$aggregate(msr("classif.ce")) # 各折均值（标量）
```

要"逐折 vs 平均"就是这两个方法的差别，`$score()` 没有 aggregate 开关。另外重复 CV 的 `$score()` 只给连续的 `iteration` 列、**不给 repeat 编号列**，想按 repeat 汇总得自己分块（迭代号按 repeat 连续排布）。
