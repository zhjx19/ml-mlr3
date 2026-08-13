# 降维与去相关

## PCA

将高维相关预测变量压缩为不相关主成分。

**何时使用**：神经网络等对共线性敏感的模型；高维数据降维。

```r
po_pca = po("pca", rank. = 5)       # 保留 5 个主成分
po_pca = po("pca", affect_columns = selector_type("numeric"))
```

## 核 PCA

用非线性核处理非线性的 PCA。

```r
po_kpca = po("kernelpca")
```

## ICA（独立成分分析）

```r
po_ica = po("ica")
```

## NMF（非负矩阵分解）

```r
po_nmf = po("nmf")
```

## 常量列剔除

```r
po_rm = po("removeconstants")      # 剔除所有单值列
```

## 过滤法去相关

通过过滤法（如信息增益）选择与目标最相关的 k 个特征，间接降维：

```r
po_filt = po("filter", flt("information_gain"), filter.nfeat = 10)
```

## 图学习器中使用

```r
glrn = po("scale") %>>%
       po("pca", rank. = 10) %>>%
       lrn("classif.rpart") |>
  as_learner()
```
