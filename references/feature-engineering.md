# 特征工程与 PipeOp（mlr3verse）

mlr3verse 的防泄露特征工程依赖 `mlr3pipelines`。原则：**任何需要从数据学习参数的预处理，都必须放进 PipeOp / GraphLearner，并在重抽样内拟合。**

## 1. 基础语法

```r
library(mlr3verse)

po()   # 查看 PipeOp 字典
ppl()  # 查看预置 pipeline

glrn = po("scale") %>>%
  po("pca", rank. = 2) %>>%
  lrn("classif.rpart") |>
  as_learner()
```

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
glrn = po("scale", affect_columns = selector_type("numeric")) %>>%
  po("encode", method = "treatment", affect_columns = selector_type("factor")) %>>%
  lrn("classif.glmnet", predict_type = "prob") |>
  as_learner()
```

常用 selector：

- `selector_type("numeric")`
- `selector_type("factor")`
- `selector_name(c("x1", "x2"))`
- `selector_invert(...)`

## 5. 模型前处理建议

| 模型族 | 必要 / 建议预处理 |
|---|---|
| 线性 / 逻辑回归 | 缺失插补、因子编码、常量列删除；可加样条和交互 |
| glmnet | 缺失插补、因子编码、常量列删除、标准化 |
| KNN / SVM | 缺失插补、one-hot、常量列删除、标准化 |
| 神经网络 | 缺失插补、one-hot、标准化、降相关 / PCA |
| 朴素贝叶斯 | 常量列删除；视实现处理缺失和因子 |
| 单棵树 | 通常无需标准化；仍需处理 learner 不支持的缺失 / 类型 |
| 随机森林 / 提升树 | 多数实现需要完整数据；通常不需标准化 |

## 6. 联合调预处理和模型参数

```r
glrn = po("encode", method = to_tune(c("treatment", "one-hot"))) %>>%
  po("pca", rank. = to_tune(2, 10)) %>>%
  lrn("classif.svm",
    cost = to_tune(1e-5, 1e5, logscale = TRUE),
    predict_type = "prob"
  ) |>
  as_learner()

at = auto_tuner(
  tuner = tnr("random_search"),
  learner = glrn,
  resampling = rsmp("cv", folds = 4),
  measure = msr("classif.auc"),
  term_evals = 30
)
```
