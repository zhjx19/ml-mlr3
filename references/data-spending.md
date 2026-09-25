# 数据划分与数据花费（mlr3verse）

本参考用于决定如何划分训练集、验证集和测试集，并保证开发期不泄露测试集信息。

## 1. 核心原则

1. **先划分，再开发**：建模流程一开始就冻结训练 / 测试划分。
2. **测试集只用于最终评估**：开发期不预测、不汇总、不可视化、不比较模型。
3. **训练集内部样本外验证**：用 CV、holdout、nested resampling 等估计性能。
4. **特殊相关结构优先于随机划分**：时间序列、分组重复观测、空间相关数据不得简单随机划分。

## 2. 标准训练 / 测试划分

```r
library(mlr3verse)

set.seed(7291)
task = as_task_classif(df, target = "outcome", positive = "yes")
split = partition(task, ratio = 0.7)

train_ids = split$train
test_ids = split$test

# 开发期只创建训练任务
train_task = task$clone(deep = TRUE)$filter(train_ids)
```

说明：

- 分类任务默认尽量保持目标变量分布。
- 测试集行号只保存，不在最终评估前使用。
- 需要保留完整 task 时，`filter()` 前必须 `$clone(deep = TRUE)`。

## 3. 三分法：训练 / 验证 / 测试

适用于大数据集或用户明确希望保留独立验证集的场景。仍然禁止使用测试集开发。

```r
set.seed(3847)
split_1 = partition(task, ratio = 0.7)
train_ids = split_1$train
temp_ids = split_1$test

temp_task = task$clone(deep = TRUE)$filter(temp_ids)
split_2 = partition(temp_task, ratio = 0.5)

valid_ids = temp_ids[split_2$train]
test_ids = temp_ids[split_2$test]
```

注意：三分法会减少训练数据；中小数据通常优先训练集内 CV。

## 4. 分组相关数据

同一个实体的多条记录不得分散到训练和测试两边，例如患者、学校、门店、用户、设备。

```r
task$set_col_roles("patient_id", roles = "group")
set.seed(4182)
split = partition(task, ratio = 0.7)
```

后续 CV 也应尊重 group 角色。

## 5. 时间序列 / 有序数据

时间序列禁止随机划分——`partition()` 会把未来数据撒进训练集；`order` 角色只作标记，**不会**改变随机重抽样的切分方式（实测：`rsmp("holdout")` 的测试集行号散布在中段）。按时间位置显式切：

```r
task = as_task_regr(time_ordered_df, target = "outcome")
task$set_col_roles("date_col", roles = "order")   # 仅作标记

n = nrow(task)
train_ids = seq_len(floor(n * 0.8))   # 前 80% 时间段训练
test_ids  = seq(floor(n * 0.8) + 1, n) # 后 20% 留作最终评估
```

训练集必须严格早于测试集。开发期用 `rsmp("custom")` 手写滚动折（内置字典无 rolling_origin），见 `resampling.md` §6。

## 6. 回归分层建议

回归任务如目标分布高度偏斜，可在训练前用目标分位数建立临时分层变量，但要避免根据测试集表现迭代调整分层策略。

概念模板：

```r
df = df |>
  mutate(outcome_stratum = cut(outcome, breaks = quantile(outcome, probs = seq(0, 1, 0.25), na.rm = TRUE), include.lowest = TRUE))

task = as_task_regr(df, target = "outcome")
task$set_col_roles("outcome_stratum", roles = "stratum")
split = partition(task, ratio = 0.7)
```

如果分层变量只用于划分，不应作为预测特征。

## 7. 禁止事项清单

- 禁止在开发期运行 `learner$predict(task, row_ids = split$test)`。
- 禁止先查看测试集分布后再决定预处理。
- 禁止用测试集挑选模型或超参数。
- 禁止测试集表现不好后返回修改模型并再次测试。
- 禁止把测试集纳入任何插补、标准化、PCA、SMOTE、特征选择的拟合过程。

## 8. 最终评估话术

当模型、调参、特征选择均已确定后，必须停下并询问：

> 模型开发已完成。是否允许我现在对保留测试集做一次最终评估？评估后不应再根据测试集结果继续调参或改模型。

用户明确同意后才能执行测试集预测。
