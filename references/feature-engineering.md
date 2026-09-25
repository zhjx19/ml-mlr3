# 特征工程与 PipeOp（mlr3verse）

mlr3verse 的防泄露特征工程依赖 `mlr3pipelines`。原则：**任何需要从数据学习参数的预处理，都必须放进 PipeOp / GraphLearner，并在重抽样内拟合。**

## 1. 基础语法

```r
library(mlr3verse)

mlr_pipeops$keys()                       # PipeOp 字典键名（下划线原样保留）
mlr_pipeops$get("splines")$param_set$ids()  # 某个 PipeOp 的参数名
ls(asNamespace("mlr3pipelines"), pattern = "^pipeline_")  # ppl() 可用的预置管道

glrn = po("scale") %>>%
  po("pca", rank. = 2) %>>%
  lrn("classif.rpart") |>
  as_learner()
```

注意：裸写 `po()` / `ppl()` **不能**列字典（报 `cannot coerce type 'environment' to vector of type 'character'`），要查就用上面的 `mlr_pipeops$keys()`。

规则：

- PipeOp 之间用 `%>>%`，不要用 `|>` 或 `%>%`。
- 图末端必须 `as_learner()`。
- 数据处理管道中的 R 代码仍用 `|>`。

## 2. 一键稳健管道

```r
glrn = ppl("robustify") %>>%
  lrn("classif.rpart", predict_type = "prob") |>
  as_learner()
```

`ppl("robustify")` 是安全起点：处理缺失、因子编码、常量列等常见问题。最终项目可根据模型和业务改成显式 PipeOp。

## 3. 常用 PipeOp 速查

### 缺失值

| PipeOp | 用途 |
|---|---|
| `imputemean` | 数值均值插补 |
| `imputemedian` | 数值中位数插补 |
| `imputemode` | 类别众数插补 |
| `imputeconstant` | 常数插补 |
| `imputeoor` | 超出范围值，常用于树模型 |
| `missind` | 增加缺失指示列 |
| `imputelearner` | 用模型插补，计算更贵 |

### 编码

| PipeOp | 用途 |
|---|---|
| `encode` | treatment / one-hot / sum / helmert 等编码 |
| `fixfactors` | 处理预测时的新水平 |
| `collapsefactors` | 合并稀有水平 |
| `encodeimpact` | 目标编码，必须在重抽样内，谨慎使用 |

### 缩放与变换

| PipeOp | 用途 |
|---|---|
| `scale` | Z-score 标准化 |
| `scalerange` | Min-Max 缩放 |
| `boxcox` | Box-Cox 变换，要求正值 |
| `yeojohnson` | 可处理零和负数的幂变换 |
| `pca` / `ica` | 降维 |
| `removeconstants` | 删除常量列 |

### 不平衡分类

| PipeOp | 用途 |
|---|---|
| `classbalancing` | 上采样 / 下采样 |
| `smote` | SMOTE |
| `smotenc` | 含分类变量的 SMOTE |

不平衡处理只能在训练折内部发生，因此必须放入图中。

## 4. 控制作用列

```r
glrn = po("scale", affect_columns = selector_type(c("numeric", "integer"))) %>>%
  po("encode", method = "treatment", affect_columns = selector_type("factor")) %>>%
  lrn("classif.glmnet", predict_type = "prob") |>
  as_learner()
```

selector 本质是 **`function(Task) -> character`**，所以 `po("select", selector = ...)` 只能传函数，传字符向量会报 `selector: Must be a function, not 'character'`（实测）；想按名字选就写 `selector_name(c("x1", "x2"))`。

常用 selector：

- `selector_type("numeric")` / `selector_type("factor")` / `selector_type(c("numeric", "integer"))`
- `selector_name(c("x1", "x2"))`
- `selector_grep("^num_")`
- `selector_invert(...)`、`selector_intersect(...)`、`selector_union(...)`
- `selector_missing()` / `selector_cardinality_greater_than(10)`
- `pos(...)`（`mlr3pipelines` 特征位置选择器，`ppl("branch")` 的分支索引用它）

三条实测坑：

1. **`integer` 不等于 `numeric`**。`data.table` 里 `1:10`、`sample(1:20, n, TRUE)` 这类列在 task 中的类型是 `integer`，`selector_type("numeric")` **选不中它们**——`po("scale")` 会静默跳过整数列。数值预处理要连整数一起作用，写 `selector_type(c("numeric", "integer"))`，或者干脆用默认的 `selector_all()`（`po("scale")` 默认对所有数值列生效，含 integer）。
2. **`$state$affected_cols` 是 selector 选中的列，不是真正被变换的列**。`po("scale")` 在该 task 上的 `affected_cols` 会把 factor 列也列进去，而实际该列原样透传；判断预处理是否真的生效，要比对 `$train()` 输出 task 的数据，别看这个字段。
3. **符号类 selector 不由 `mlr3verse` 再导出**。`selector_positive` / `selector_negative` / `selector_non_negative` / `selector_non_positive` / `selector_non_zero` / `selector_non_missing` 这六个要加 `mlr3pipelines::` 前缀；哪些 selector 在 `mlr3verse` 里，现探 `grep("^selector", getNamespaceExports("mlr3verse"))`。另外**根本没有 `neg()` 这个函数**（`pos()` 有），取反请写 `selector_invert(...)`。

其它 PipeOp 的类型前置（实测）：

| PipeOp | 约束 | 报错 |
|---|---|---|
| `boxcox` | 作用列必须全为正值 | `x must be positive`（含负值/零时改用 `yeojohnson`） |
| `splines` | 默认作用全部列，遇 factor 崩 | `non-numeric argument to binary operator`，须 `affect_columns = selector_type("numeric")` |
| `subsample` | `stratify = TRUE` 与内部按组抽样互斥 | `Cannot combine stratification with grouping`，须同时 `use_groups = FALSE` |
| `pca` / `ica` / `nmf` | 只吃数值矩阵 | 有 factor 列时先 `encode`，或用 `affect_columns` 限定 |

## 5. 模型前处理建议

| 模型族 | 必要 / 建议预处理 |
|---|---|
| 线性 / 逻辑回归 | 缺失插补、因子编码、常量列删除；可加样条和交互 |
| glmnet | 缺失插补、因子编码、常量列删除、标准化 |
| KNN / SVM | 缺失插补、one-hot、常量列删除、标准化 |
| 神经网络 | 缺失插补、one-hot、标准化、降相关 / PCA |
| 朴素贝叶斯 | 常量列删除；视实现处理缺失和因子 |
| 单棵树 | 通常无需标准化；仍需处理 learner 不支持的缺失 / 类型 |
| 随机森林 / 提升树 | 多数实现需要完整数据；通常不需标准化。注意 ranger / xgboost **不接受 factor 列**（实测报 `<TaskClassif:...> has the following unsupported feature types: factor`），必须先 `po("encode")` 或走 `ppl("robustify")` |

## 6. 联合调预处理和模型参数

```r
glrn = po("encode", method = to_tune(c("treatment", "one-hot"))) %>>%
  po("pca", rank. = to_tune(2, 10)) %>>%
  lrn("classif.svm",
    type = "C-classification",               # 必须显式设：cost 是条件参数
    kernel = "radial",                        # 必须显式设：gamma 是条件参数
    cost = to_tune(1e-5, 1e5, logscale = TRUE),
    predict_type = "prob"
  ) |>
  as_learner()

at = auto_tuner(
  tuner = tnr("random_search"),
  learner = glrn,
  resampling = rsmp("cv", folds = 4),
  measure = msr("classif.ce"),
  term_evals = 30
)
```

图里带 `classif.svm` 时，`type` / `kernel` 忘了显式设置，`at$train()` 会在调优第一步就报 `Assertion on 'xs' failed: classif.svm.cost: can only be set if ... type == C-classification`（实测：PipeOp 参数 `to_tune()` 不会改变这个前置条件）。

## 7. 日期时间列与惰性物化

`ppl("robustify")` 里的 `POSIXct_to_dbl` 只做**一次线性映射到数值**，不会展开日历特征。要从日期里取年/月/周/星期等特征，显式放 `po("datefeatures")`：

```r
po_df = po("datefeatures", cyclic = TRUE)          # 周期性展开：sin/cos
po_df$train(list(task_date))
out = po_df$predict(list(task_date))[[1L]]
out$feature_names      # 含 dt.month_sin, dt.month_cos, dt.year, dt.day_of_week ...
```

有哪些开关现探就行：`mlr_pipeops$get("datefeatures")$param_set$ids()`（`cyclic`、`keep_date_var` 加逐特征开关）。要记住的是**输出列名规则** `<原列名>.<特征名>`，`cyclic = TRUE` 时再带 `_sin` / `_cos` 后缀——后面 `$select()` 和 `affect_columns` 都得按这个拼。

Date / POSIXct 列可以**直接进插补 PipeOp**（实测 `po("imputemedian")`、`po("imputehist")` 对含 NA 的 Date 列 `$train()` 正常出结果），不必先手动转数值。

调试或把 task 交给不吃 Task 的外部函数时，用物化：

```r
glrn_dbg = (po("removeconstants") %>>% po("materialize") %>>% lrn("classif.rpart")) |> as_learner()
view = task$clone(deep = TRUE)$filter(1:30)$materialize_view()   # 冻结成 data.frame 视图
```

`po("materialize")` 无参数，作用是在图中把该点之后的 task 数据落地。

