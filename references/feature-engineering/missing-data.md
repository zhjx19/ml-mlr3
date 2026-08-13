# 缺失数据

## 概述

mlr3verse 提供 8 种缺失值插补 PipeOp。

## 简单插补

```r
po("imputemean")       # 均值插补（数值列）
po("imputemedian")     # 中位数插补
po("imputemode")       # 众数插补（因子列）
po("imputeconstant",   # 常数插补
   constant = -999,
   affect_columns = selector_name("glucose"))
```

## 随机抽样插补

```r
po("imputesample")     # 从训练数据非缺失值随机抽样
po("imputehist")       # 从估计分布抽样（保留分布特征）
```

## 学习器插补

```r
po("imputelearner", lrn("regr.rpart"))                   # 决策树
po("imputelearner",
   po("imputehist") %>>% lrn("regr.kknn"))               # 链式 KNN
```

## 超出范围插补（树兼容）

```r
glrn = po("imputeoor") %>>%       # 因子加 .MISSING 水平，数值用最大值+1
       po("missind") %>>%         # 增加是否缺失指示列
       lrn("classif.xgboost") |>
  as_learner()
```

## 一键管道

```r
# ppl("robustify") 自动处理缺失值 + 因子编码 + 零方差
glrn = ppl("robustify") %>>% lrn("classif.rpart") |> as_learner()
```
