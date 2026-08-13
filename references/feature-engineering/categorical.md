# 分类预测变量编码

## 虚拟变量（指示编码）

将 K 个水平的分类变量转为 K-1 个二值列（某一水平为参照）。
线性模型、神经网络、SVM、KNN 必须使用。

**要点**：
- 参照水平影响系数解释，不影响预测
- 高基数变量产生大量列 → 考虑目标编码

### mlr3verse

```r
# treatment 编码（K-1 列）
po_encode = po("encode", method = "treatment")

# one-hot 编码（K 列）
po_encode = po("encode", method = "one-hot")
```

## 目标编码

用基于结局的数值替换分类水平。适用于高基数分类变量。

**要点**：
- 重抽样内处理防泄漏
- 平滑/正则化有助于罕见水平

### mlr3verse

```r
# 影响编码（需安装 mlr3extralearners）
po_encode = po("encodeimpact")

# 混合效应编码
po_encode = po("encodelmer")
```

## 新水平处理

测试/生产数据中出现训练集未见的因子水平时出错。

```r
# 将新水平设为 "other"
po_fix = po("fixfactors")
```

## 罕见水平合并

```r
# 合并出现比例低于 5% 的水平
po_collapse = po("collapsefactors", no_collapse_above_prevalence = 0.05)
```

## 图学习器中使用

```r
glrn = po("collapsefactors") %>>%
       po("fixfactors") %>>%
       po("encode", method = "treatment") %>>%
       lrn("classif.glmnet") |>
  as_learner()
```
