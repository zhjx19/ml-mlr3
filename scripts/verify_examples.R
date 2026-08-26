#!/usr/bin/env Rscript
# -*- coding: utf-8 -*-
# verify_examples.R —— ml-mlr3 skill 核心骨架一键回归脚本
#
# 逐项实跑 SKILL.md 的最小骨架与关键工作流，证明示例代码在当前
# mlr3verse 版本下可运行。改动 SKILL.md 示例代码后跑一遍本脚本。
#
# 本脚本自身遵守 R 铁律：= 赋值、|> 管道、\(x) 匿名函数；
# mlr3pipelines 按全局铁律例外使用 %>>%。
#
# 用法（skill 目录下）：
#   Rscript scripts/verify_examples.R
# 退出码：0 = 全部 PASS；1 = 任一 FAIL。
suppressPackageStartupMessages({
  library(mlr3verse)
  library(data.table)
})

run_case = \(name, code) {
  status = tryCatch(
    { force(code); "PASS" },
    error = \(e) paste("FAIL:", conditionMessage(e))
  )
  cat(sprintf("[%s] %s\n", status, name))
  setNames(status, name)
}

# 二元分类数据（iris 抽两类）——注意用 skill 推荐的非常见种子
df_bin = iris[iris$Species %in% c("setosa", "versicolor"), ]
df_bin$Species = factor(df_bin$Species, levels = c("setosa", "versicolor"))
set.seed(7291)

results = c(
  ## 最小骨架：分类
  run_case("最小骨架·分类", {
    task = as_task_classif(df_bin, target = "Species", positive = "setosa")
    split = partition(task, ratio = 0.7)
    train_task = task$clone(deep = TRUE)$filter(split$train)
    measures = msrs(c("classif.auc", "classif.ce", "classif.acc"))
    glrn = ppl("robustify") %>>% lrn("classif.rpart", predict_type = "prob") |> as_learner()
    rr = resample(train_task, glrn, rsmp("cv", folds = 3), store_models = TRUE)
    a = rr$aggregate(measures)
    stopifnot(is.finite(a[["classif.auc"]]))
    TRUE
  }),

  ## 最小骨架：回归
  run_case("最小骨架·回归", {
    task = as_task_regr(mtcars, target = "mpg")
    split = partition(task, ratio = 0.7)
    train_task = task$clone(deep = TRUE)$filter(split$train)
    measures = msrs(c("regr.rmse", "regr.rsq"))
    glrn = ppl("robustify") %>>% lrn("regr.rpart") |> as_learner()
    rr = resample(train_task, glrn, rsmp("cv", folds = 3), store_models = TRUE)
    a = rr$aggregate(measures)
    stopifnot(is.finite(a[["regr.rmse"]]))
    TRUE
  }),

  ## auto_tuner（含 svm 条件参数修复：type / kernel 必须显式设置）
  run_case("auto_tuner（svm 条件参数）", {
    task = as_task_classif(df_bin, target = "Species", positive = "setosa")
    split = partition(task, ratio = 0.7)
    train_task = task$clone(deep = TRUE)$filter(split$train)
    at = auto_tuner(
      tuner = tnr("random_search"),
      learner = lrn("classif.svm",
        type = "C-classification", kernel = "radial",
        cost = to_tune(1e-2, 1e2, logscale = TRUE),
        gamma = to_tune(1e-3, 1, logscale = TRUE), predict_type = "prob"),
      resampling = rsmp("cv", folds = 3),
      measure = msr("classif.auc"),
      term_evals = 5
    )
    at$train(train_task)
    stopifnot(!is.null(at$tuning_result))
    TRUE
  }),

  ## ppl("branch") 备选路径调参
  run_case("ppl(branch) 分支调参", {
    task = as_task_classif(df_bin, target = "Species", positive = "setosa")
    split = partition(task, ratio = 0.7)
    train_task = task$clone(deep = TRUE)$filter(split$train)
    prep = ppl("branch", pos(c("nop", "pca")))
    prep$update_ids(prefix = "prep_")
    graph = prep %>>% ppl("branch", lrns(c("classif.rpart", "classif.kknn")))
    glrn = as_learner(graph)
    glrn$param_set$values$prep_branch.selection = to_tune(c("nop", "pca"))
    glrn$param_set$values$branch.selection = to_tune(c("classif.rpart", "classif.kknn"))
    at = auto_tuner(
      tuner = tnr("random_search"), learner = glrn,
      resampling = rsmp("cv", folds = 3), measure = msr("classif.ce"), term_evals = 4)
    at$train(train_task)
    stopifnot(!is.null(at$tuning_result))
    TRUE
  }),

  ## benchmark：比较经调优的算法（小规模）
  run_case("benchmark 调优后比较", {
    task = as_task_classif(df_bin, target = "Species", positive = "setosa")
    split = partition(task, ratio = 0.7)
    train_task = task$clone(deep = TRUE)$filter(split$train)
    at_rpart = auto_tuner(tuner = tnr("random_search"),
      learner = lrn("classif.rpart", predict_type = "prob"),
      search_space = ps(cp = p_dbl(0.001, 0.1, logscale = TRUE)),
      resampling = rsmp("cv", folds = 3), measure = msr("classif.auc"), term_evals = 4)
    at_ranger = auto_tuner(tuner = tnr("random_search"),
      learner = lrn("classif.ranger", predict_type = "prob"),
      search_space = ps(mtry = p_int(1, 2)),
      resampling = rsmp("cv", folds = 3), measure = msr("classif.auc"), term_evals = 4)
    design = benchmark_grid(tasks = train_task, learners = list(at_rpart, at_ranger),
                            resamplings = rsmp("cv", folds = 3))
    bmr = benchmark(design)
    a = bmr$aggregate(msr("classif.auc"))
    stopifnot(nrow(a) == 2)
    TRUE
  })
)

## 汇总
fails = names(results)[results != "PASS"]
cat(sprintf("\n=== 汇总：%d/%d PASS ===\n", sum(results == "PASS"), length(results)))
if (length(fails) > 0) {
  for (f in fails) cat("FAIL:", f, "->", results[[f]], "\n")
  quit(status = 1)
}
quit(status = 0)
