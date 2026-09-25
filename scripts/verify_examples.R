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

run_case = \(name, code, no_warn = FALSE) {
  status = tryCatch(
    {
      if (no_warn) {
        withCallingHandlers(force(code),
          warning = \(w) stop(sprintf("意外警告（视为失败）: %s", conditionMessage(w)), call. = FALSE))
      } else {
        force(code)
      }
      "PASS"
    },
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

  ## 时序：显式时间切分 + rsmp("custom") 滚动折
  ## （mlr3 内置字典无 rolling_origin；order 角色不改变随机 CV 切分方式）
  run_case("时序·custom 滚动折", {
    d_ts = data.table(
      day = seq(as.Date("2024-01-01"), by = "day", length.out = 60),
      x1  = rnorm(60),
      y   = rnorm(60))
    task_ts = as_task_regr(d_ts, target = "y")
    task_ts$set_col_roles("day", roles = "order")
    n_ts = task_ts$nrow
    tr_ids = seq_len(floor(n_ts * 0.8))
    tr_task = task_ts$clone(deep = TRUE)$filter(tr_ids)
    n_tr = tr_task$nrow
    b1 = floor(n_tr * 0.55); b2 = floor(n_tr * 0.70); b3 = floor(n_tr * 0.85)
    rc = rsmp("custom")
    rc$instantiate(tr_task,
      train = list(1:b1,        1:b2,        1:b3),
      test  = list((b1 + 1):b2, (b2 + 1):b3, (b3 + 1):n_tr))
    # 时间因果性：每折测试集最小行号必须严格大于训练集最大行号。
    # 不能写 all(rc$test_set(k) > rc$train_set(k))——两向量长度不同时 R 会循环补齐，
    # 断言退化成空断言（只比较前 min(length) 个元素），测试集可能已泄露进训练集却仍然 PASS。
    causal = \(k) min(rc$test_set(k)) > max(rc$train_set(k))
    stopifnot(causal(1), causal(2), causal(3))
    rr_ts = resample(tr_task, lrn("regr.rpart"), rc)
    a_ts = rr_ts$aggregate(msr("regr.rmse"))
    stopifnot(is.finite(a_ts[["regr.rmse"]]))
    TRUE
  }, no_warn = TRUE),

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
  }),

  ## 早停：set_validate() + 内部验证分数 + msr("best_valid_score")
  ## （learner 参数 validate 已不存在；nrounds = to_tune(internal = TRUE) 只能进 auto_tuner，
  ##   直接 $train() 会报 "cannot be trained with TuneToken present"）
  run_case("早停·best_valid_score", {
    d_es = data.table(
      y = factor(rep(c("a", "b"), each = 60)),
      x1 = rnorm(120), x2 = rnorm(120), x3 = rnorm(120))
    t_es = as_task_classif(d_es, target = "y", positive = "a")
    stopifnot(all(c("best_valid_score", "internal_valid_score") %in% mlr_measures$keys()))
    lrn_es = lrn("classif.xgboost", predict_type = "prob", nrounds = 150L,
                 early_stopping_rounds = 10L, eval_metric = "logloss")
    set_validate(lrn_es, validate = 0.3)
    lrn_es$train(t_es)
    stopifnot(!is.null(lrn_es$internal_tuned_values$nrounds))
    stopifnot(is.finite(lrn_es$internal_valid_scores$logloss))
    # 注意 select 用指标名（此处 "logloss"），不是 score_id / param_vals
    stopifnot(is.finite(lrn_es$internal_valid_scores[["logloss"]]))
    rr_es = resample(t_es, lrn_es, rsmp("cv", folds = 3))
    a_es = rr_es$aggregate(msrs(c("classif.auc", "best_valid_score")))
    stopifnot(is.finite(a_es[["classif.auc"]]), is.finite(a_es[["best_valid_score"]]))
    TRUE
  }),

  ## Selector：整数列覆盖 + 符号/缺失选择器（Selector 接收 Task，返回列名）
  ## library(mlr3verse) 只再导出部分 selector_*，符号类需 mlr3pipelines:: 前缀
  run_case("selector·整数列与符号选择器", {
    set.seed(3847)
    d_s = data.table(
      y = factor(rep(c("a", "b"), each = 50)),
      x_pos = abs(rnorm(100)),
      x_neg = -abs(rnorm(100)),
      x_int = as.integer(rpois(100, 3)))
    d_s$x_na = c(NA_real_, rnorm(99))
    t_s = as_task_classif(d_s, target = "y", positive = "a")
    po_num = po("scale", affect_columns = selector_type("numeric"))
    po_num$train(list(t_s))
    po_ni = po("scale", affect_columns = selector_type(c("numeric", "integer")))
    po_ni$train(list(t_s))
    stopifnot(!("x_int" %in% po_num$state$affected_cols))
    stopifnot("x_int" %in% po_ni$state$affected_cols)
    stopifnot(identical(mlr3pipelines::selector_positive(na_ignore = TRUE)(t_s), "x_pos"))
    stopifnot(identical(selector_missing()(t_s), "x_na"))
    stopifnot(!("x_na" %in% mlr3pipelines::selector_non_missing()(t_s)))
    glrn = (po("scale", affect_columns = selector_type(c("numeric", "integer"))) %>>%
      lrn("classif.rpart")) |> as_learner()
    glrn$train(t_s)
    stopifnot(length(glrn$predict(t_s)$response) == t_s$nrow)
    TRUE
  }),

  ## ppl("greplicate")（独立函数 greplicate() 已移除）+ po("materialize")
  ## greplicate 产出 n 个输出通道，必须接 po("featureunion") 再进学习器
  run_case("greplicate + materialize", {
    d_g = data.table(y = factor(rep(c("a", "b"), each = 40)), x1 = rnorm(80), x2 = rnorm(80))
    t_g = as_task_classif(d_g, target = "y", positive = "a")
    glrn_rep = (ppl("greplicate", graph = po("pca"), n = 3L) %>>%
      po("featureunion") %>>% lrn("classif.rpart")) |> as_learner()
    glrn_rep$train(t_g)
    stopifnot(length(glrn_rep$predict(t_g)$response) == t_g$nrow)
    glrn_mat = (po("removeconstants") %>>% po("materialize") %>>%
      lrn("classif.rpart")) |> as_learner()
    glrn_mat$train(t_g)
    stopifnot(!is.null(glrn_mat$model))
    # Task 侧同名方法：把 filter()/cbind() 造成的虚拟视图落盘，减少 backend 嵌套
    t_view = t_g$clone(deep = TRUE)$filter(1:30)$materialize_view()
    stopifnot(t_view$nrow == 30L, identical(t_view$feature_names, t_g$feature_names))
    TRUE
  }),

  ## po("datefeatures")：Date/POSIXct 展开成日历特征（树模型不吃 Date 列）
  run_case("datefeatures 日历展开", {
    d_d = data.table(
      y = factor(rep(c("a", "b"), each = 30)),
      dt = as.Date("2024-01-01") + (1:60))
    t_d = as_task_classif(d_d, target = "y", positive = "a")
    stopifnot(t_d$feature_types$type == "Date")
    po_df = po("datefeatures", cyclic = TRUE)
    po_df$train(list(t_d))
    t_out = po_df$predict(list(t_d))[[1L]]
    stopifnot(!("dt" %in% t_out$feature_names))
    stopifnot(all(c("dt.month_sin", "dt.month_cos", "dt.year") %in% t_out$feature_names))
    stopifnot(!("Date" %in% t_out$feature_types$type))
    glrn = (po("datefeatures") %>>% lrn("classif.rpart")) |> as_learner()
    glrn$train(t_d)
    stopifnot(length(glrn$predict(t_d)$response) == t_d$nrow)
    TRUE
  }),

  ## Task 访问器语义：cols() / nrow() / row_ids() 已不是方法
  ## （nrow / row_ids / feature_names / target_names / positive 是字段，写成 () 调用即报错）
  ## 另注：positive 要求目标列只有 2 个 level——子集后的 iris 仍带 3 个 level，必须先 droplevels()
  run_case("Task·访问器语义", {
    t_a = as_task_classif(droplevels(iris[1:100, ]), target = "Species", positive = "setosa")
    # feature_names 按字母序返回，不保持数据列顺序
    stopifnot(setequal(t_a$feature_names, c("Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width")))
    stopifnot(identical(t_a$target_names, "Species"))
    stopifnot(t_a$nrow == 100L, length(t_a$row_ids) == 100L)
    stopifnot(identical(t_a$positive, "setosa"))
    stopifnot(is.integer(t_a$n_features) || is.numeric(t_a$n_features))
    # missings() 是方法，返回命名数值向量
    d_m = data.table(y = factor(rep(c("a", "b"), each = 25)), x1 = c(NA_real_, rnorm(49)), x2 = rnorm(50))
    t_m = as_task_classif(d_m, target = "y", positive = "a")
    mi = t_m$missings()
    stopifnot(all(names(mi) %in% c("y", "x1", "x2")), mi[["x1"]] == 1L, mi[["x2"]] == 0L)
    # 已不存在的旧 API：调用必须报错，防止文档写回
    errored = \(expr) inherits(tryCatch(force(expr), error = identity), "error")
    stopifnot(errored(t_a$cols()), errored(t_a$nrow()), errored(t_a$row_ids()),
              errored(t_a$correlation()))
    TRUE
  }),

  ## 调参档案的两个尺度/类型陷阱：
  ## 1) to_tune(c(1, 3, 5)) 使 archive 列变 character；to_tune(p_int()) 保持 integer
  ## 2) archive$data / tuning_result 的连续参数列是 trafo 后尺度，真实值在 x_domain
  run_case("调参档案·dtype 与 trafo 尺度", {
    d_t = data.table(y = factor(rep(c("a", "b"), each = 50)), x1 = rnorm(100), x2 = rnorm(100))
    t_t = as_task_classif(d_t, target = "y", positive = "a")
    at = auto_tuner(
      tuner = tnr("random_search"),
      learner = lrn("classif.rpart",
        cp = to_tune(0.01, 0.1, logscale = TRUE),
        minbucket = to_tune(c(1L, 3L, 5L)),
        maxdepth = to_tune(p_int(2L, 6L))),
      resampling = rsmp("cv", folds = 3), measure = msr("classif.ce"), term_evals = 4)
    at$train(t_t)
    stopifnot(is.character(at$archive$data$minbucket))
    stopifnot(is.integer(at$archive$data$maxdepth))
    real_cp = at$tuning_result$x_domain[[1L]]$cp
    stopifnot(real_cp > 0.009, real_cp < 0.11)
    stopifnot(at$tuning_result$cp < 0)  # logscale 后的内部尺度，不能当 cp 用
    stopifnot(nrow(at$tuning_result) == 1L, nrow(at$archive$data) == 4L)
    TRUE
  }),

  ## learner$deadline：具名 numeric，名字限 {"train", "predict"}，值为绝对时刻
  run_case("learner$deadline", {
    d_l = data.table(y = factor(rep(c("a", "b"), each = 40)), x1 = rnorm(80), x2 = rnorm(80))
    t_l = as_task_classif(d_l, target = "y", positive = "a")
    lrn_ok = lrn("classif.rpart")
    lrn_ok$deadline = c(train = as.numeric(Sys.time()) + 60)
    lrn_ok$train(t_l)
    stopifnot(!is.null(lrn_ok$model))
    lrn_bad = lrn("classif.rpart")
    rejected = tryCatch({ lrn_bad$deadline = c(foo = 1); FALSE },
                        error = \(e) TRUE)
    stopifnot(rejected)
    TRUE
  }),

  ## 字典探针：文档里点名的对象必须真实存在（防止写入不存在的键 / 已移除的旧用法）
  run_case("字典探针·文档点名对象", {
    keys_po = mlr_pipeops$keys()
    expect_po = c("scale", "pca", "imputemean", "imputemedian", "imputemode", "imputeoor",
      "missind", "imputelearner", "encode", "fixfactors", "collapsefactors", "encodeimpact",
      "scalerange", "yeojohnson", "removeconstants", "classbalancing", "smote", "smotenc",
      "ica", "isomap", "materialize", "datefeatures", "splines", "branch", "unbranch",
      "featureunion", "learner", "learner_cv", "replicate", "ovrsplit", "ovrunite",
      "targettrafoscalerange")
    missing_po = setdiff(expect_po, keys_po)
    if (length(missing_po) > 0L) stop(sprintf("PipeOp 字典缺键: %s", paste(missing_po, collapse = ", ")))
    # pipeline 构造器不在 mlr_pipeops 字典里（ppl() 走 pipeline_* 函数），逐个构造验证
    # 形参名以 formals() 为准：greplicate(graph, n) / branch(graphs) / ovr(graph)
    # stacking(base_learners, super_learner) / targettrafo(graph) / convert_types(type_from, type_to)
    step = \(label, expr) tryCatch({ force(expr); TRUE }, error = \(e) FALSE)
    stopifnot(step("robustify", ppl("robustify")))
    stopifnot(step("greplicate", ppl("greplicate", graph = po("pca"), n = 2L)))
    stopifnot(step("branch", ppl("branch", lrns(c("classif.rpart", "classif.featureless")))))
    stopifnot(step("ovr", ppl("ovr", graph = lrn("classif.rpart"))))
    stopifnot(step("targettrafo", ppl("targettrafo", graph = lrn("regr.rpart"))))
    stopifnot(step("convert_types", ppl("convert_types", type_from = "character", type_to = "factor")))
    stopifnot(step("stacking", ppl("stacking", base_learners = list(lrn("classif.rpart", predict_type = "prob")),
      super_learner = lrn("classif.featureless", predict_type = "prob"))))
    expect_msr = c("classif.auc", "classif.ce", "classif.acc", "classif.prauc", "classif.fbeta",
      "classif.mbrier", "regr.rmse", "regr.mae", "regr.rsq", "best_valid_score",
      "internal_valid_score")
    stopifnot(length(setdiff(expect_msr, mlr_measures$keys())) == 0L)
    expect_tnr = c("grid_search", "random_search", "gensa", "cmaes", "irace", "mbo",
      "successive_halving", "hyperband", "async_random_search", "async_grid_search")
    stopifnot(length(setdiff(expect_tnr, mlr_tuners$keys())) == 0L)
    # 旧特征选择器名 forward / backward / bonu 已不在字典中，引用它们的写法必须改掉
    stopifnot(length(intersect(c("forward", "backward", "bonu"), mlr_fselectors$keys())) == 0L)
    expect_fs = c("sequential", "random_search", "exhaustive_search", "genetic_search",
      "rfe", "rfecv", "shadow_variable_search")
    stopifnot(length(setdiff(expect_fs, mlr_fselectors$keys())) == 0L)
    expect_lrn = c("classif.glmnet", "classif.ranger", "classif.xgboost", "classif.svm",
      "classif.kknn", "classif.rpart", "classif.featureless", "classif.lightgbm",
      "classif.catboost", "classif.nnet", "regr.lightgbm", "regr.ranger")
    stopifnot(length(setdiff(expect_lrn, mlr_learners$keys())) == 0L)
    expect_task = c("diabetes", "german_credit", "mtcars", "iris", "penguins", "titanic",
      "breast_cancer", "sonar")
    stopifnot(length(setdiff(expect_task, mlr_tasks$keys())) == 0L)
    # 已移除的旧用法不得复活：独立函数 greplicate()、任务 pima
    stopifnot(!exists("greplicate"))
    stopifnot(!("pima" %in% mlr_tasks$keys()))
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
