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
# 必须显式限定作用列：po("splines") 默认 affect_columns = selector_all()，
# 遇到 factor 列会崩在内部 quantile() 上，报错信息是 "non-numeric argument to binary
# operator"（实测），完全看不出是类型问题。
po_spline = po("splines", type = "natural", df = 5,
               affect_columns = selector_type("numeric"))
```

实测约束：`type` 只接受 `"natural"` 与 `"polynomial"`（写 `"b-spline"` 报 Must be element of set）；`knots` 必须是 **list**（每个作用列一条），给标量数字报 `Must be of type 'list'`；`df = 5` 时每个数值列展开成 `x1.splines.1 … x1.splines.5`，原列仍保留。

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
