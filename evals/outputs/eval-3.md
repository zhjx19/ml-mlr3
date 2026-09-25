# 回答：月度销售数据（时间序列）的划分与重抽样

时间序列**禁止随机划分和随机 CV**——随机打乱后模型会用未来数据预测过去。先说两个容易踩的坑（按技能包的现场探测纪律核对）：

1. **内置重抽样字典里没有 `rolling_origin`**（只有 bootstrap/custom/custom_cv/cv/holdout/insample/loo/repeated_cv/subsampling），网上旧教程的 `rsmp("rolling_origin")` 会直接报 `not found in DictionaryResampling`。
2. **`order` 角色只作时间标记，不会让随机 CV / holdout 按时间切分**——实测设置后 holdout 的测试集照样散布在中段。

正确姿势：按时间位置显式切分 + `rsmp("custom")` 手写滚动折。

```r
library(mlr3verse)
library(data.table)

sales = fread("sales.csv")
setorder(sales, date)   # 确保按时间升序

task = as_task_regr(sales, target = "monthly_sales")
task$set_col_roles("date", roles = "order")   # 仅作标记，不改变随机切分

# 1) 训练/测试按时间位置切：前 80% 训练，后 20% 留作最终评估（现在不动它）
n = nrow(task)
train_ids = seq_len(floor(n * 0.8))
test_ids  = seq(floor(n * 0.8) + 1, n)
train_task = task$clone(deep = TRUE)$filter(train_ids)

# 2) 开发期：rsmp("custom") 手写滚动折，训练窗严格早于验证窗
n_tr = train_task$nrow
b1 = floor(n_tr * 0.55); b2 = floor(n_tr * 0.70); b3 = floor(n_tr * 0.85)
rc = rsmp("custom")
rc$instantiate(train_task,
  train = list(1:b1,        1:b2,        1:b3),
  test  = list((b1 + 1):b2, (b2 + 1):b3, (b3 + 1):n_tr))

glrn = ppl("robustify") %>>%
  lrn("regr.rpart") |>
  as_learner()

rr = resample(train_task, glrn, rc)
rr$aggregate(msr("regr.rmse"))
```

要点：

- 每个折的训练窗都早于验证窗，模拟真实的"用历史预测下个月"；验证窗长度应与你的预测 horizon（1 个月）一致，窗数按数据量取 3-5 折。
- 后 20% 时间段保留不动，模型定型后经你授权做一次最终评估（时间上严格晚于全部训练数据）。
