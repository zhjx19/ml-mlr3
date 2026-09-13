# 回答：房价回归（高基数分类 + 偏斜数值）

规范流程：训练集内 CV 比较 glmnet 与随机森林；`ppl("robustify")` 起步——它含 one-hot 编码（25 个水平的 neighborhood 可直接吃）与常数列清理；偏斜数值变量如需 Yeo-Johnson 变换可加 `po("yeojohnson")` 分支（需 bestNormalize 包）。评估附 RMSE/MAE/R² 与观测 vs 预测、残差图。

```r
library(mlr3verse)
library(data.table)

set.seed(8341)
housing = fread("housing.csv")

task = as_task_regr(housing, target = "SalePrice")
split = partition(task, ratio = 0.7)
train_task = task$clone(deep = TRUE)$filter(split$train)

measures = msrs(c("regr.rmse", "regr.mae", "regr.rsq"))

glrn_glmnet = ppl("robustify") %>>%
  lrn("regr.glmnet") |>
  as_learner()
glrn_ranger = ppl("robustify") %>>%
  lrn("regr.ranger", num.trees = 500) |>
  as_learner()

design = benchmark_grid(train_task, list(glrn_glmnet, glrn_ranger),
                        resamplings = rsmp("cv", folds = 5))
bmr = benchmark(design, store_models = TRUE)
bmr$aggregate(measures)

# 评估可视化：观测 vs 预测 + 残差（以 glmnet 为例）
rr = resample(train_task, glrn_glmnet, rsmp("cv", folds = 5))
pred_data = as.data.table(rr$prediction())

pred_data |>
  ggplot(aes(x = truth, y = response)) +
  geom_point(alpha = 0.3) +
  geom_abline(color = "red", linetype = "dashed") +
  labs(x = "Observed", y = "Predicted")

pred_data |>
  mutate(residual = truth - response) |>
  ggplot(aes(x = response, y = residual)) +
  geom_point(alpha = 0.3) +
  geom_hline(yintercept = 0, color = "red")
```

残差若呈喇叭形，下一步考虑对目标做对数变换再比一轮。并行与测试集评估照例：先经你确认。
