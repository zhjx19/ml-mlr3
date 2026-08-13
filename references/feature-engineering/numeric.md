# 数值预测变量变换

## 中心化与缩放（标准化）

将预测变量变为均值为 0、方差为 1。距离/点积模型（KNN、SVM、神经网络、正则化回归、PCA）必须使用。

**要点**：
- 训练集计算均值和标准差，测试集应用相同值
- 树模型不需要

### mlr3verse

```r
# Z-score 标准化
po_scale = po("scale")

# Min-Max 归一化到 [0, 1]
po_range = po("scalerange", lower = 0, upper = 1)

# 行规范化（L2 范数）
po_sign = po("spatialsign")
```

## 对称变换

将偏态预测变量近似对称。改善线性模型和神经网络性能。

### mlr3verse

Box-Cox（仅正值）：
```r
po_bc = po("boxcox")
```

Yeo-Johnson（推荐，可处理零值和负数）：
```r
po_yj = po("yeojohnson")
```

## 样条项

为线性模型建模预测变量与结果的非线性关系。

**要点**：
- df 控制灵活度，df 越高越摆荡
- 从 3-5 开始，必要时调优

```r
po_spline = po("splines", type = "natural", df = 5)
```

## 交互项

建模两个或更多预测变量的联合效应。

```r
# 用 formula 语法
po_mm = po("modelmatrix", formula = ~ .^2)                    # 所有主效应 + 二阶交互
po_mm = po("modelmatrix", formula = ~ poly(x1, 2, raw = TRUE))# 一元二次
po_mm = po("modelmatrix", formula = ~ polym(x1, x2, degree = 2, raw = TRUE)) # 二元二次
```

## 自定义特征

```r
po_feat = po("mutate", mutation = list(
  fare_per_person = ~ fare / (parch + sib_sp + 1)
))
```

## 零方差剔除

```r
po_const = po("removeconstants")  # 剔除所有常量列
```
