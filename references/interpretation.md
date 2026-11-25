# 模型解释：SHAP（kernelshap + shapviz）

**解释的是模型，不是因果。** SHAP 把某个预测值拆成「各特征相对参照人群推高/拉低了多少」，它回答"模型为什么这么判"，不回答"改这个特征会不会改变结果"。

边界三条：

- 开发期只解释**训练集**的行（含训练集内 CV 的预测对象）；解释**测试集**个案属于红线 1，先获授权。
- 预处理必须已经封装在图学习器里（红线 3）——SHAP 解释的就是「图 + 学习器」这条完整流水线。
- 本章模板针对 xgboost；lightgbm / catboost / ranger 只换「取底层模型 + 调它的 predict」那一步，`kernelshap` 与 `shapviz` 不变。

## 1. 依赖

```r
# 都不在 mlr3verse 里，运行前确认
requireNamespace("kernelshap", quietly = TRUE)   # 精确 Kernel SHAP
requireNamespace("shapviz", quietly = TRUE)      # 图：bar / beeswarm / waterfall / force
```

各提升树库自带的 SHAP（`xgboost::xgb.plot.shap`、`shapviz` 对 `xgb.Booster` 的直接方法）只能解释**单模型**，解释不了图学习器，也不能统一回归/分类口径。本技能统一走 `kernelshap`（模型无关，只要求给一个 `pred_fun`）。

## 2. 模板：四步

```r
library(mlr3verse)
library(data.table)

# ① 模型：预处理在图里，SHAP 解释的是整条流水线
task = tsk("sonar")
split = partition(task, ratio = 0.7)
train_task = task$clone(deep = TRUE)$filter(split$train)
glrn = ppl("robustify") %>>%
  lrn("classif.xgboost", predict_type = "prob", nrounds = 100L, nthread = 1L) |>
  as_learner()
glrn$train(train_task)

# ② 快速预测函数：直接调底层 booster，不要走 predict_newdata
#    predict_newdata() 每次调用都重建 Task：实测 40 次调用 11.7 s，直调 booster 0.13 s（约 90 倍）
#    图学习器的末端模型会被包成 list("wrapper")，真身在 attr(m[[1]], "model")；普通学习器无此包装
get_booster = \(object) {
  m = if (inherits(object$model, "graph_learner_model")) {
    object$model[[length(object$model)]]$model
  } else {
    object$model
  }
  if (is.list(m) && !inherits(m, "xgb.Booster")) m = attr(m[[1]], "model")
  m
}
pred_xgb = \(object, X, ...) {
  predict(get_booster(object), newdata = data.matrix(X)) |> as.numeric()
}

# ③ 解释谁（X）＋ 跟谁比（bg_X）：参照人群决定 baseline
X_explain = train_task$data(
  rows = train_task$row_ids[1:5], cols = train_task$feature_names)
set.seed(3847)
bg_X = train_task$data(
  rows = sample(train_task$row_ids, 100), cols = train_task$feature_names)

pshap = kernelshap(
  glrn, X = X_explain, bg_X = bg_X,
  feature_names = train_task$feature_names, pred_fun = pred_xgb,
  parallel = TRUE, m = 200, seed = 3847)      # m 必须是偶数；200 让全部观测收敛

# 可加性校验：baseline + 各行 SHAP 之和 = 模型预测值（数值上应接近 0）
max(abs(rowSums(pshap$S) + pshap$baseline - as.numeric(pshap$predictions)))

# ④ 图
sv = shapviz(pshap)
sv_importance(sv, kind = "bar", max_display = 10)       # 全局重要性 = 平均 |SHAP|
sv_importance(sv, kind = "beeswarm", max_display = 10)  # 方向 + 分布
sv_waterfall(sv, row_id = 1)                            # 单个案：从 baseline 推到预测值
sv_force(sv, row_id = 1, max_display = 10)              # 同一个个案的"力"视图
```

二分类时 `pred_fun` 返回的是**正类概率**向量（xgboost 二分类的 `predict()` 就是向量）；多分类返回概率矩阵，`kernelshap` 会按多输出返回，`shapviz` 需按类别现查 `?shapviz` 的口径。回归同理，返回数值向量即可。

## 3. 六个坑

1. **`predict_newdata()` 是性能陷阱**。Kernel SHAP 要成百上千次预测，每次都重建 Task 就不是"慢一点"，是慢两个数量级（实测约 90 倍）。这也解释了为什么不能图省事写 `pred_fun = \(object, X, ...) object$predict_newdata(X)$prob[, "M"]`——算得对，但跑不完。
2. **`bg_X` 决定 baseline**。同一病人、同一预测值，把参照人群从"全体病人"换成"健康人"，`baseline` 整体下移、各特征贡献变大。报告里必须写清"相对于哪个人群"；抽 100–200 行并按目标分层。
3. **`m` 与收敛**。默认 `m = 5p` 时约四分之一观测不收敛；书里用 `m = 200` 让全部观测收敛。收敛的判据就是可加性校验那一行——差得远就加 `m`。
4. **`m` 必须偶数**。`kernelshap` 0.9.1 实测：`m = 15` 直接报 `m must be even`。
5. **并行走 future**。`kernelshap` 内部用 `%dofuture%`，`registerDoParallel()` 对它无效；`parallel = TRUE` 前先 `future::plan()`（档位按 SKILL.md 红线 5），跑完复原。它的并行单位是解释行/重复抽样，不是重抽样折。
6. **最终模型没有早停日志，但 SHAP 照用**。`auto_tuner` 的最终模型是全训练集重拟合，`$internal_tuned_values` 为空；SHAP 解释最终模型完全没问题，别去找"最终模型的早停曲线"（见 `advanced-workflows.md` §5）。

## 4. 报错对照

| 报错原文 | 病因 | 修法 |
|---|---|---|
| `m must be even` | `m` 给成奇数 | 改成偶数（200 / 300） |
| `Assertion on 'rows' failed: Must be a subset of {...}` | 过滤后的 task 行号不是 1:n | 用 `train_task$row_ids` 下标取行，别写 `1:5` |
| `could not find function "kernelshap"` | 没装包（不在 mlr3verse） | `install.packages(c("kernelshap", "shapviz"))` |
| `no applicable method for 'predict'` | `get_booster()` 拿到的还是 list（包装层没剥） | 打印 `class()` 逐层看，取到 `xgb.Booster` 再调 `predict()` |
| 可加性差很多（> 1e-4） | `m` 太小 / `bg_X` 太小 | 加 `m`，`bg_X` 抽到 100–200 行 |
| `The following packages could not be loaded: precrec` 一类 | 图渲染缺 Suggests 后端 | 见 `evaluation.md` §6.5，装对应后端 |

## 5. 报告里怎么写

三句话模板：

- 全局：`特征 A 与 B 的平均绝对 SHAP 最大`（配合 bar / beeswarm）。
- 个案：`该样本被判高风险，主要因为 A 把预测从 baseline 0.31 推到 0.78`（配合 waterfall）。
- 限定：`以上均相对于 <bg_X 描述>，SHAP 解释模型而非因果`。
