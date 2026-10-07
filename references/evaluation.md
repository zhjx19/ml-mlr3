# 模型评估、可视化与最终报告（mlr3verse）

模型评估分为两类：开发期训练集内部样本外评估，以及用户授权后的最终测试集评估。二者必须严格区分。

## 1. 评估原则

1. 开发期只使用训练集内部重抽样预测。
2. 模型比较必须基于相同任务、相同重抽样、相同指标。
3. 最终测试集只评估一次，且必须先获得用户许可。
4. 指标选择要与业务目标一致，不平衡分类不能只看准确率。

## 2. 分类指标

### 2.1 阈值无关指标

| 指标 | mlr3 key | 用途 |
|---|---|---|
| ROC-AUC | `classif.auc` | 排序能力，常用默认 |
| PR-AUC | `classif.prauc` | 不平衡数据优先 |
| Logloss | `classif.logloss` | 概率质量，越小越好 |
| Brier | `classif.mbrier` | 概率校准，越小越好 |

```r
pred$score(msrs(c("classif.auc", "classif.prauc", "classif.mbrier")))
```

### 2.2 阈值相关指标

| 指标 | mlr3 key | 用途 |
|---|---|---|
| Accuracy | `classif.acc` | 类别均衡时直观 |
| Balanced Accuracy | `classif.ba` | 类别不平衡时比 acc 稳健 |
| Recall | `classif.recall` | 正例捕获率 |
| Precision | `classif.precision` | 预测正例可信度 |
| F1 / F-beta | `classif.fbeta` | precision / recall 折中 |

```r
pred$score(msrs(c(
  "classif.acc", "classif.ba", "classif.recall",
  "classif.precision", "classif.fbeta"
)))
pred$confusion
```

## 3. 回归指标

| 指标 | mlr3 key | 用途 |
|---|---|---|
| RMSE | `regr.rmse` | 默认主指标，惩罚大误差 |
| MAE | `regr.mae` | 稳健误差 |
| R² | `regr.rsq` | 解释比例，不能替代 RMSE/MAE |
| MAPE | `regr.mape` | 百分比误差，目标接近 0 时谨慎 |

```r
pred$score(msrs(c("regr.rmse", "regr.mae", "regr.rsq")))
```

## 4. 可视化：选图决策表与分类可视化

图统一由 **mlr3viz** 画：`autoplot()` 是 ggplot2 的泛型，mlr3viz 为各 mlr3 对象挂 S3 方法，`type` 参数决定从同一对象上画哪一种。**mlr3viz 是 `mlr3verse` 的硬依赖**（`packageDescription("mlr3verse")$Imports` 里有 `mlr3viz (>= 0.10.0)`），`library(mlr3verse)` 之后 `autoplot` 即可用（由 mlr3verse 再导出），**不需要** `library(mlr3viz)`，也不需要单独安装。默认套 `ggplot2::theme_minimal()`，配色走 viridis。

### 4.1 场景 → 图 决策表

选图两步：**先定"要回答什么问题"** → 决定对象类型；**再定 `type`**。同一份 `rr` 能画五六种图，选错对象（拿 `pred` 画本应看折间波动的图）比选错 `type` 更常见。

| 场景（我要回答什么） | 对象 | 调用 | 前提 |
|---|---|---|---|
| 建模前：类别是否不平衡 / 目标分布 | Task | `autoplot(task, type = "target")` | — |
| 建模前：特征两两关系、异常点 | Task | `autoplot(task, type = "pairs")`（`"duo"` 仅分类） | `GGally` |
| 开发期：**折间稳定性**（不只看均值） | ResampleResult | `autoplot(rr, type = "boxplot")` | — |
| 开发期：单模型分数分布形态 | ResampleResult | `autoplot(rr, type = "histogram")` | — |
| 二分类：**判别力**（阈值无关） | ResampleResult / PredictionClassif / BenchmarkResult | `autoplot(x, type = "roc")`；不平衡改 `"prc"` | `predict_type = "prob"`；`precrec` |
| 二分类：**定决策阈值**（代价不对称） | PredictionClassif | `autoplot(pred, type = "threshold", measure = msr("classif.fbeta"))` | 二分类 |
| 二分类：错在哪些类 | PredictionClassif | `autoplot(pred, type = "stacked")` | — |
| 回归：**拟合诊断** | PredictionRegr | `autoplot(pred, type = "xy")`、`autoplot(pred, type = "residual")` | — |
| 回归：残差分布形态 | PredictionRegr | `autoplot(pred, type = "histogram", binwidth = 1)` | — |
| 回归：带标准误的置信带 | PredictionRegr | `autoplot(pred, type = "confidence")` | `predict_type = "se"` |
| 模型比较（多算法 / 多任务） | BenchmarkResult | `autoplot(bmr, type = "boxplot", measure = msr("classif.auc"))` | — |
| 模型比较：多条 ROC 同图 | BenchmarkResult | `autoplot(bmr, type = "roc")` | 恰好 1 task + 1 重抽样 |
| 调优：收敛过程 / 最优值轨迹 | TuningInstance | `autoplot(instance, type = "performance")`、`"incumbent"` | — |
| 调优：单个超参的响应 | TuningInstance | `autoplot(instance, type = "marginal", cols_x = "cp")` | — |
| 调优：超参相互作用 | TuningInstance | `autoplot(instance, type = "points", cols_x = c("cp", "minsplit"))`、`"pairs"`、`"parallel"` | — |
| 调优：性能曲面 | TuningInstance | `autoplot(instance, type = "surface", cols_x = c("a", "b"))` | 两个超参**都**是连续型（见 §6.3） |
| 特征筛选打分 | Filter | `autoplot(flt, n = 10)` | `mlr3filters` |
| 决策边界 / CV 预测曲面 | Learner / ResampleResult | `autoplot(learner, type = "prediction", task)`、`autoplot(rr, type = "prediction")` | 分类恰好 **2** 特征；回归 1–2 特征；`rr` 需 `store_models = TRUE` |

图是数值指标之外的**必附**项，不是替代项：分类必附 ROC（不平衡换 PR）+ 阈值图，回归必附 xy + 残差。测试集图只在获授权后画一次。

### 4.2 二分类：先看判别力，再定阈值

```r
# pred = learner$predict(task)，learner 需 predict_type = "prob"
autoplot(pred, type = "stacked")   # 真值 vs 预测类别，先看错的是哪一类
autoplot(pred, type = "roc")       # 判别力，阈值无关
autoplot(pred, type = "prc")       # 不平衡数据优先看这条
autoplot(pred, type = "threshold", measure = msr("classif.fbeta"))   # 定决策点
```

`roc` / `prc` 需 learner 设了 `predict_type = "prob"`，否则报 `Need predicted probabilities to plot a ROC curve`；还依赖 `precrec`（在 mlr3viz 的 Suggests 里，mlr3verse 不带）。不平衡数据优先展示 PR 曲线，并解释 accuracy 的局限。`threshold` 用 `measure` 指定优化目标——不同 `measure` 会给出不同最优阈值，报告里要写清用的是哪个。

`roc` / `prc` / `threshold` 都只对**二分类**成立；多分类任务要用 macro AUC 等指标代替，别指望这三张图。

### 4.3 用 `rr` 还是 `rr$prediction()`

两者不是同一个口径，报告里必须写清用了哪个：

```r
autoplot(rr, type = "roc")                  # 折间合并后计算（mlr3viz 手册：micro averaged）
autoplot(rr$prediction(), type = "roc")     # 合并预测对象上计算
```

`rr$aggregate(msr("classif.auc"))` 是**逐折 AUC 的均值**，与上面两条曲线各自的 AUC 都不相等。三者数值接近不等于口径相同——写报告时指明用的是"逐折均值"还是"合并预测"，否则无法复现。

## 5. 回归可视化

mlr3viz 自带回归预测的成套图，**不要手写 ggplot**：`autoplot(PredictionRegr)` 的 `type` 已覆盖 `xy`（默认）、`residual`、`histogram`、`confidence`。手写 ggplot 还有一层坑：`library(mlr3verse)` **不 attach ggplot2**，裸调 `ggplot()` / `aes()` / `geom_point()` 会直接报 `could not find function "ggplot"`（`autoplot` 能用只是因为 mlr3verse 把它再导出了）。

```r
autoplot(pred, type = "xy")                     # 观测 vs 预测 + slope=1 参考线 + lm 趋势线
autoplot(pred, type = "residual")               # 残差 vs 预测——查系统性偏差与异方差
autoplot(pred, type = "histogram", binwidth = 1)  # 残差分布形态
```

图自带的图元（实测 `$layers`）：`xy` 是四层——`GeomAbline`（`intercept = 0, slope = 1` 参考线，默认黑色、`alpha = 0.5`）、`GeomPoint`（散点，viridis 蓝 `#31678EFF`、`alpha = 0.8`）、`GeomRug`（边际地毯图）、`GeomSmooth`（`method = "lm"` 趋势线，viridis 青 `#21908CFF`，默认带置信带）。注意**参考线与趋势线都不是红色**——手动加的 `geom_abline(color = "red")` 才是红的，那是自己的图层，别把两者混淆。

读图要点：`xy` 上点云偏离 slope = 1 参考线说明存在系统性高/低估；`residual` 上呈喇叭形说明异方差、呈弯月形说明模型漏了非线性结构。

`type = "confidence"` 需 learner 设 `predict_type = "se"`（如 `regr.lm`、`regr.ranger`），否则报 `Plot type 'confidence' only possible when \`predict_type = 'se'\``：

```r
autoplot(pred_se, type = "confidence")   # pred_se 来自 predict_type = "se" 的 learner
```

确实要自己改图（加标注、换配色）时才需要 ggplot2，并且必须显式 `library(ggplot2)` 或用 `ggplot2::` 前缀：`autoplot(pred, type = "xy", theme = ggplot2::theme_bw())`——`theme` 默认传的是 `ggplot2::theme_minimal()`，裸写 `theme_bw()` 会报 `could not find function "theme_bw"`。

## 6. 重抽样、benchmark、调优与筛选可视化

### 6.1 ResampleResult：先看折间波动

```r
autoplot(rr, type = "boxplot")                                   # 各折分数分布
autoplot(rr, type = "boxplot", measure = msr("classif.auc"))
autoplot(rr, type = "histogram", bins = 10)
autoplot(rr, type = "prediction")                                # 需 store_models = TRUE
```

箱线图回答的是"这个分数稳不稳"——`rr$aggregate()` 只给你均值，把折间方差藏起来了。分类任务的 `type = "prediction"` 要求任务**恰好两个特征**（报错原文 `Plot learner prediction only works for tasks with two features for classification!`）；回归支持 1–2 个特征，单特征时 learner 设 `predict_type = "se"` 可叠加置信带。想看训练集与测试集一起画出，传 `predict_sets = c("train", "test")`（**下划线**，且 learner 需 `predict_sets` 含这两个集合）。

### 6.2 BenchmarkResult：比较模型

```r
design = benchmark_grid(
  tasks = train_task,
  learners = list(learner_glmnet, learner_xgb, learner_rf),
  resamplings = rsmp("cv", folds = 5)
)

bmr = benchmark(design, store_models = TRUE)
bmr$aggregate(msrs(c("classif.auc", "classif.ce", "classif.acc")))
autoplot(bmr, type = "boxplot", measure = msr("classif.auc"))
```

所有候选必须在相同训练任务和相同重抽样下比较。禁止用测试集比较模型。

`type = "roc"` / `"prc"` 要求该 benchmark **只有一个任务、一个重抽样**，否则报 `Unable to convert benchmark results with multiple tasks.`——多任务时先 `$filter(task_ids = "xxx")` 切出单任务再画。`type = "ci"` 画置信区间，需传 `mlr3inferr` 的 `msr("ci", ...)`。

### 6.3 TuningInstance：判断调优有没有真的在收敛

```r
autoplot(instance, type = "performance")                     # 批次 vs 性能
autoplot(instance, type = "incumbent")                       # 最优值随评估次数的轨迹
autoplot(instance, type = "marginal", cols_x = "cp")          # 单参数响应 + 批次着色
autoplot(instance, type = "parameter")                        # 批次 vs 参数，颜色=性能
autoplot(instance, type = "parallel")                         # 参数平行坐标
autoplot(instance, type = "points", cols_x = c("cp", "minsplit"))   # 两参数散点，颜色=性能
autoplot(instance, type = "pairs")                            # 全参数两两对照
```

`incumbent` 还在下降 = 预算不够，别急着下"该算法不行"的结论；`marginal` / `points` 用来判断参数是否已收敛到边界（最优值贴在上界通常意味着搜索空间划窄了）。

这些图**返回两类不同对象，落盘方式因此不同**：`performance` / `incumbent` / `parallel` / `points` 返回 `ggplot`，`ggsave()` 直接可用；而 `marginal` / `parameter` 返回 patchwork 的 **`DelayedPatchworkPlot`** 延迟对象——它只注册了 `print` 方法，`ggsave()` 会报 `no applicable method for 'grid.draw' applied to an object of class "DelayedPatchworkPlot"`（**`library(patchwork)` 也救不了**）。这几张图落盘要走图形设备 + `print()`：

```r
png("tuning-parameter.png", width = 1200, height = 700, res = 120)
print(autoplot(instance, type = "parameter"))
dev.off()
```

`pairs` 返回 GGally 的 `ggmatrix`（需 `GGally`），`ggsave()` 可用。

`type = "surface"` 有前提：**两个超参都必须是连续型**，只要其中一个是整数型（`minsplit`、`maxdepth` 这类），当前版本会报 `Incompatible types during auto-converting column 'minsplit': failed to convert from class 'numeric' to class 'integer'`（`p_int()` 显式声明也拦不住）。含整数超参时改用 `points` / `marginal` / `pairs` 看同样的信息。`surface` 的插值学习器由 `learner` 参数给（默认 `regr.ranger`）。

### 6.4 Filter：看特征打分

```r
flt_sel = flt("correlation")
flt_sel$calculate(train_task)
autoplot(flt_sel, n = 10)
```

只接受 `type = "boxplot"`（默认）；手册 description 写的 `"barplot"` 是笔误，实测传它会报 `Assertion on 'type' failed: Must be element of set {'boxplot'}, but is 'barplot'.`。`n` 控制只画打分最高的前 n 个特征。

### 6.5 前置条件与报错原文对照表

下列报错都实测复现过。看到其中任何一条，先按"缺什么"补，不要去改图画代码：

| 报错原文 | 缺什么 |
|---|---|
| `Need predicted probabilities to plot a ROC curve` | learner 的 `predict_type = "prob"` |
| `Plot type 'confidence' only possible when \`predict_type = 'se'\`` | learner 的 `predict_type = "se"` |
| `No trained models available. Set 'store_models = TRUE' in 'resample()'.` | `resample(..., store_models = TRUE)` |
| `Plot learner prediction only works for tasks with two features for classification!` | 任务选到恰好 2 个特征（分类） |
| `Unable to convert benchmark results with multiple tasks.` | 先 `$filter(task_ids = ...)` 切出单任务 |
| `could not find function "ggplot"` / `"theme_bw"` | `library(ggplot2)` 或用 `ggplot2::` 前缀 |
| `Assertion on 'type' failed: Must be element of set {'boxplot'}, but is 'barplot'.` | Filter 只接受 `type = "boxplot"` |
| `Incompatible types during auto-converting column '...'` | `surface` 的两个超参须都是连续型 |

依赖侧：`roc` / `prc` 需 `precrec`，`pairs` / `duo`（Task 与调优）需 `GGally`，`ci` 需 `mlr3inferr`，调优的 `marginal` / `parameter` 返回 patchwork 对象（`patchwork` 在 mlr3viz 的 Suggests 里），glmnet / rpart 学习器图需 `ggfortify` / `ggparty`——这些都在 **mlr3viz 的 Suggests** 里，mlr3verse 的依赖链上**没有**，干净机器上画这几张图前要先 `install.packages()`。不要额外包的是：Task `target`、`boxplot`、`histogram`、回归 `xy` / `residual` / `histogram`、`confidence`、分类 `stacked` / `roc` / `prc` / `threshold`，以及调优的 `performance` / `incumbent` / `parallel` / `points`。

### 6.6 主题与定制

所有图都接受 `theme`，默认 `ggplot2::theme_minimal()`；配色走 viridis。mlr3viz 返回的**多数**是普通 `ggplot` 对象，可直接接 `+` 继续叠图层（`marginal` / `parameter` 的 patchwork 对象与 `pairs` 的 `ggmatrix` 不适用，见下）：

```r
autoplot(rr, type = "boxplot", measure = msr("classif.auc")) +
  ggplot2::labs(title = "5 折 CV：classif.auc") +
  ggplot2::theme_bw()
```

`autoplot` 返回对象可直接交给 `ggplot2::ggsave()` 落盘（画图脚本常见需求），但记得先 `library(ggplot2)`。**例外是调优的 `marginal` / `parameter`**：它们返回 `DelayedPatchworkPlot`，`ggsave()` 不适用，改用 `print()` + `png()`/`dev.off()`（见 §6.3）。

图对象类型对不上时先 `class(p)` 看一眼——本文件涉及四类：`ggplot`（绝大多数）、`ggmatrix`（Task 的 `pairs`/`duo`、调优的 `pairs`，需 `GGally`）、`DelayedPatchworkPlot`（调优的 `marginal`/`parameter`）、以及组合图（`patchwork`）。

## 7. 最终模型训练

用户选定最终模型后，在全训练集拟合：

```r
final_learner = chosen_learner$clone(deep = TRUE)
final_learner$train(task, row_ids = split$train)
```

如果 `chosen_learner` 是 `auto_tuner()` 或 `auto_fselector()`，`$train()` 会在训练集内完成内层选择，并用最佳配置拟合全训练集。

## 8. 测试集最终评估

先停下询问用户。获得许可后：

```r
final_pred = final_learner$predict(task, row_ids = split$test)
final_scores = final_pred$score(measures)
```

报告时明确：这是一次性保留测试集最终评估，不再基于结果继续调参或改模型。
