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

# ── 文档口径自检（不计入用例数）：本项目的版本号必须三处一致 ──────────────────────
# 为什么钉在这里、且钉在 library() 之前：历史上这个仓库有过两份平行的版本元数据
# （marketplace 声明文件 vs SKILL.md），结果是"两个通道版本号各说各话"。那份声明文件已归档
# 移除，但同一个坑还会再踩——版本号只要抄在两个地方就会分家。现在唯一的权威是三处本仓库
# 自己的文本：SKILL.md frontmatter、README 的版本段、CHANGELOG 最新**已发布**条目。
# 放在依赖库之前，是因为元数据不一致时不该还要等 mlr3verse 加载起来才告诉你。
ver_num = function(x) {
  m = regmatches(x, gregexpr("[0-9]+[.][0-9]+[.][0-9]+", x, perl = TRUE))
  if (length(m) && length(m[[1]])) m[[1]][1] else NA_character_
}
meta_check = function(root = ".") {
  f_sk = file.path(root, "SKILL.md"); f_rd = file.path(root, "README.md"); f_cl = file.path(root, "CHANGELOG.md")
  if (!all(file.exists(f_sk, f_rd, f_cl))) {
    cat("[SKIP] 版本自洽检查：三个文件没都在（root =", normalizePath(root, mustWork = FALSE), "）\n")
    return(invisible(TRUE))
  }
  v_sk = ver_num(grep("^version:", readLines(f_sk, warn = FALSE), value = TRUE)[1])
  ln_rd = grep("当前发布版本", readLines(f_rd, warn = FALSE), value = TRUE)
  v_rd = if (length(ln_rd)) ver_num(ln_rd[1]) else NA_character_
  rel_cl = grep("^## [[][0-9]", readLines(f_cl, warn = FALSE), value = TRUE)   # 跳过 [Unreleased]
  v_cl = if (length(rel_cl)) ver_num(rel_cl[1]) else NA_character_
  got = c(SKILL = v_sk, README = v_rd, CHANGELOG = v_cl)
  if (any(is.na(got)))
    stop("版本号缺失：", paste(sprintf("%s=%s", names(got), got[!is.na(got)]), collapse = " "),
      call. = FALSE)
  if (!identical(unique(got), v_sk) || length(unique(got)) != 1L)
    stop(sprintf("三处版本号不一致: SKILL=%s README=%s CHANGELOG=%s", v_sk, v_rd, v_cl), call. = FALSE)
  cat(sprintf("[OK] 版本自洽 v%s（SKILL.md / README.md / CHANGELOG.md 三处一致）\n", v_sk))
  invisible(TRUE)
}
meta_check(if (file.exists("SKILL.md")) "." else if (file.exists("../SKILL.md")) ".." else ".")

suppressPackageStartupMessages({
  library(mlr3verse)
  library(data.table)
})

skip = \(why) stop(structure(list(message = why, call = NULL),
  class = c("skipCondition", "error", "condition")))
envir_ref = new.env(parent = emptyenv())   # run_case 内部传递 SKIP 原因
envir_times = new.env(parent = emptyenv()) # 用例名 -> 实跑秒数
wall_t0 = proc.time()[["elapsed"]]

run_case = \(name, code, no_warn = FALSE) {
  t0 = proc.time()[["elapsed"]]
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
    error = \(e) {
      if (inherits(e, "skipCondition")) {
        assign("last_skip", conditionMessage(e), envir = envir_ref)
        "SKIP"
      } else paste("FAIL:", conditionMessage(e))
    }
  )
  secs = proc.time()[["elapsed"]] - t0
  assign(name, secs, envir = envir_times)          # 计时账，汇总时点名"快到可疑"的用例
  extra = if (identical(status, "SKIP") && !is.null(envir_ref$last_skip)) paste0(" — ", envir_ref$last_skip) else ""
  if (identical(status, "SKIP")) envir_ref$last_skip = NULL
  cat(sprintf("[%s] %s%s (%.1fs)\n", status, name, extra, secs))
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
    # 学习器键分两组。分组的依据是实测的分发通道差异，不是想放宽什么：
    # mlr3verse / mlr3learners 在 CRAN 上，装完就该有下面这批键；而 mlr3extralearners **不在 CRAN**
    # （官方通道是 mlr-org 的 r-universe），干净机器上没装它时 classif.lightgbm 一类键压根不在字典里。
    # 混在一条无条件断言里，红的是"这台机器装了哪些包"，而不是"文档有没有幻觉"——病因就错了。
    expect_lrn = c("classif.glmnet", "classif.ranger", "classif.xgboost", "classif.svm",
      "classif.kknn", "classif.rpart", "classif.featureless", "classif.nnet", "regr.ranger")
    miss_lrn = setdiff(expect_lrn, mlr_learners$keys())
    if (length(miss_lrn)) stop(sprintf("CRAN 版 mlr3verse 字典缺键: %s", paste(miss_lrn, collapse = ", ")))
    expect_task = c("diabetes", "german_credit", "mtcars", "iris", "penguins", "titanic",
      "breast_cancer", "sonar")
    stopifnot(length(setdiff(expect_task, mlr_tasks$keys())) == 0L)
    # 已移除的旧用法不得复活：独立函数 greplicate()、任务 pima
    stopifnot(!exists("greplicate"))
    stopifnot(!("pima" %in% mlr_tasks$keys()))
    # 软锚点组放在最后：SKIP 会中断本例，前面的 CRAN 基线断言必须已经跑完。
    # 探针实测（2026-09-26）：mlr3extralearners "已安装但未加载"时键就已经在字典里
    # （library(mlr3verse) 下 keys() 已含 classif.lightgbm，加载前后都是 285 个），故守卫用 requireNamespace。
    if (!requireNamespace("mlr3extralearners", quietly = TRUE))
      skip("mlr3extralearners 未安装（不在 CRAN，需 mlr-org r-universe），lightgbm / catboost 键待核验")
    miss_extra = setdiff(c("classif.lightgbm", "regr.lightgbm", "classif.catboost"), mlr_learners$keys())
    if (length(miss_extra)) stop(sprintf("mlr3extralearners 已装却缺键: %s", paste(miss_extra, collapse = ", ")))
    TRUE
  }),

  ## PipeOp 类型前置：文档里点明的三条约束必须真实成立（实测反证已在 references/feature-engineering.md §4）
  run_case("PipeOp 类型前置·splines/boxcox/subsample/select", {
    set.seed(5127)
    d_p = data.table(x1 = rgamma(120, 2, 2), x2 = rnorm(120) * 10 + 50,
                     xn = rnorm(120) - 3, x_int = sample(1:20, 120, TRUE),
                     g = factor(sample(c("low", "mid", "high"), 120, TRUE)))
    d_p$y = factor(ifelse(d_p$x1 > median(d_p$x1), "a", "b"))
    t_p = as_task_classif(d_p, target = "y", positive = "a")
    errored = \(expr) inherits(tryCatch(force(expr), error = identity), "error")
    # 1) splines：默认 affect_columns = selector_all() → 遇 factor 崩；限定 numeric 才可用
    stopifnot(errored(po("splines", type = "natural", df = 5)$train(list(t_p))))
    sp = po("splines", type = "natural", df = 5, affect_columns = selector_type(c("numeric", "integer")))
    t_sp = sp$train(list(t_p))[[1L]]
    stopifnot(all(paste0("x1.splines.", 1:5) %in% t_sp$feature_names))
    stopifnot(errored(po("splines", type = "b-spline")))          # type 只有 natural / polynomial
    stopifnot(errored(po("splines", knots = 3)))                  # knots 必须是 list
    # 2) boxcox 要求正值，yeojohnson 可处理负值
    stopifnot(errored(po("boxcox", affect_columns = selector_name("xn"))$train(list(t_p))))
    yj = po("yeojohnson", affect_columns = selector_name("xn"))
    stopifnot(!is.null(yj$train(list(t_p))))
    # 3) subsample：stratify = TRUE 必须配 use_groups = FALSE
    stopifnot(errored(po("subsample", frac = 0.5, stratify = TRUE)$train(list(t_p))))
    ss = po("subsample", frac = 0.5, stratify = TRUE, use_groups = FALSE)
    stopifnot(ss$train(list(t_p))[[1L]]$nrow == 60L)
    # 4) po("select") 的 selector 必须是函数
    stopifnot(errored(po("select", selector = c("x1", "x2"))))
    sel = po("select", selector = selector_name(c("x1", "x2")))
    stopifnot(identical(sel$train(list(t_p))[[1L]]$feature_names, c("x1", "x2")))
    TRUE
  }),

  ## selector 语义：integer 不等于 numeric；$state$affected_cols 不等于"真正被变换的列"
  run_case("selector·integer 与 affected_cols 语义", {
    d_s = data.table(y = factor(rep(c("a", "b"), each = 20)), xi = as.integer(1:40),
                     xd = as.numeric(1:40), gf = factor(rep(c("p", "q"), 20)))
    t_s = as_task_classif(d_s, target = "y", positive = "a")
    stopifnot(identical(unname(t_s$feature_types[t_s$feature_types$id == "xi", ]$type), "integer"))
    p_num = po("scale", affect_columns = selector_type("numeric")); p_num$train(list(t_s))
    p_ni = po("scale", affect_columns = selector_type(c("numeric", "integer"))); p_ni$train(list(t_s))
    stopifnot(!("xi" %in% p_num$state$affected_cols))             # selector_type("numeric") 漏掉整数列
    stopifnot("xi" %in% p_ni$state$affected_cols)
    # 默认 affect_columns 把 factor 列也列为候选，但实际原样透传 → 该字段不能当"生效证据"
    p_def = po("scale"); t_def = p_def$train(list(t_s))[[1L]]
    stopifnot("gf" %in% p_def$state$affected_cols)
    stopifnot(identical(as.character(t_def$data()$gf), as.character(d_s$gf)))
    stopifnot(is.numeric(t_def$data()$xi))                        # 默认下整数列确实被缩放为 numeric
    # 符号类 selector 不在 mlr3verse 的导出集里（用导出集判断，不受 search path 污染）
    exp_v = getNamespaceExports("mlr3verse")
    exp_p = getNamespaceExports("mlr3pipelines")
    sign_sel = c("selector_positive", "selector_negative", "selector_non_negative",
      "selector_non_positive", "selector_non_zero", "selector_non_missing")
    stopifnot(all(sign_sel %in% exp_p), !any(sign_sel %in% exp_v))
    stopifnot("pos" %in% exp_v, !("neg" %in% exp_p))   # neg() 根本不存在，取反用 selector_invert
    d_pos = data.table(y = factor(rep(c("a", "b"), each = 6)), xp = c(1, 2, 3, 4, 5, 6),
                       xn = -c(1, 2, 3, 4, 5, 6), zl = c(0, 1, 0, 1, 0, 1))
    t_pos = as_task_classif(d_pos, target = "y", positive = "a")
    stopifnot(identical(mlr3pipelines::selector_positive()(t_pos), "xp"))
    stopifnot(identical(mlr3pipelines::selector_negative()(t_pos), "xn"))
    stopifnot(identical(mlr3pipelines::selector_non_negative()(t_pos), c("xp", "zl")))
    TRUE
  }),

  ## 文档签名冒烟：references/feature-engineering.md §6 与 references/tuning.md §1.3 的写法必须能训练
  run_case("文档签名·图调参与 lts 预置空间", {
    if (!requireNamespace("mlr3tuningspaces", quietly = TRUE))
      skip("mlr3tuningspaces 未安装（文档已注明需单独安装）")
    set.seed(9137)
    d_g = data.table(y = factor(rep(c("a", "b"), 60)), x1 = rnorm(120), x2 = rt(120, 3),
                     g = factor(sample(c("p", "q", "r"), 120, TRUE)))
    t_g = as_task_classif(d_g, target = "y", positive = "a")
    # ranger / svm 本体不吃 factor 列（实测报 "unsupported feature types: factor"），
    # 单学习器用例只给数值特征 task；带 factor 的 t_g 留给走 encode 的图用例。
    t_num = t_g$clone(deep = TRUE)$select(c("x1", "x2"))
    suppressPackageStartupMessages(library(mlr3tuningspaces))
    # §1.3：lts() 返回 TuningSpace R6；$learner 只是 learner id 字符串，真正的 learner 靠 $get_learner()
    lts_obj = lts("classif.ranger.default")
    stopifnot(inherits(lts_obj, "TuningSpace"), is.character(lts_obj$learner))
    stopifnot(length(lts_obj$values) > 0L)
    lrn_pre = lts_obj$get_learner()
    stopifnot(inherits(lrn_pre, "LearnerClassifRanger"))
    stopifnot(all(names(lrn_pre$param_set$values) %in% lrn_pre$param_set$ids()))
    # get_learner() 每次给独立克隆：改了 a 不应影响 b（红线 2 的 R6 引用纪律同样适用于预置空间）
    lrn_b = lts_obj$get_learner()
    lrn_pre$param_set$values$num.trees = 7L
    stopifnot(inherits(lrn_b$param_set$values$num.trees, "TuneToken"))
    # 未编码就喂 factor：ranger 直接报错，说明预置空间不替你处理类型（必须配 encode / robustify）
    stopifnot(inherits(tryCatch(lrn_pre$train(t_g), error = identity), "error"))
    at_r = auto_tuner(tuner = tnr("random_search"), learner = lrn_pre,
      resampling = rsmp("cv", folds = 3), measure = msr("classif.ce"), term_evals = 2)
    at_r$train(t_num)
    stopifnot(nrow(at_r$tuning_result) == 1L)
    # svm.default 空间仍受条件参数前置约束：不设 type 直接 train 必须报断言错
    mk_svm = \(extra) {
      l = lts("classif.svm.default")$get_learner()
      for (nm in names(extra)) l$param_set$values[[nm]] = extra[[nm]]
      auto_tuner(tuner = tnr("random_search"), learner = l,
        resampling = rsmp("cv", folds = 3), measure = msr("classif.ce"), term_evals = 1)
    }
    errored = \(expr) inherits(tryCatch(force(expr), error = identity), "error")
    stopifnot(errored(mk_svm(list())$train(t_num)))                # 不设 type → 断言失败
    at_s = mk_svm(list(type = "C-classification", cost = 1))
    at_s$train(t_num)
    stopifnot(nrow(at_s$tuning_result) == 1L)
    # §6：图 + PipeOp to_tune + svm（显式 type/kernel）
    glrn = (po("encode", method = to_tune(c("treatment", "one-hot"))) %>>%
      po("pca", rank. = to_tune(2, 5)) %>>%
      lrn("classif.svm", type = "C-classification", kernel = "radial",
        cost = to_tune(1e-2, 1e2, logscale = TRUE), predict_type = "prob")) |> as_learner()
    at_g = auto_tuner(tuner = tnr("random_search"), learner = glrn,
      resampling = rsmp("cv", folds = 3), measure = msr("classif.ce"), term_evals = 2)
    at_g$train(t_g)
    tun_names = names(at_g$tuning_result)
    stopifnot(all(c("encode.method", "pca.rank.", "classif.svm.cost") %in% tun_names))
    stopifnot(at_g$tuning_result[["pca.rank."]] >= 2L && at_g$tuning_result[["pca.rank."]] <= 5L)
    stopifnot(at_g$tuning_result[["encode.method"]] %in% c("treatment", "one-hot"))
    TRUE
  }),

  ## 重抽样实测坑：bootstrap 重复主键 / 封装兜底 / 分层口径 / 线程参数
  run_case("重抽样实测坑·bootstrap/封装兜底/分层/线程", {
    if (!requireNamespace("ranger", quietly = TRUE)) skip("ranger 未安装，跳过线程参数断言")
    set.seed(9137)
    n_b = 200L
    d_b = data.table(x1 = rnorm(n_b), x2 = rnorm(n_b))
    d_b$y = factor(fifelse(d_b$x1 + d_b$x2 > 0.8, "min", "maj"), levels = c("min", "maj"))
    t_b = as_task_classif(d_b, target = "y", positive = "min")
    errored_b = \(expr) inherits(tryCatch(force(expr), error = identity), "error")

    # 1) rsmp() 没有 stratify；分层靠 stratum 列角色
    stopifnot(errored_b(rsmp("cv", folds = 5L, stratify = TRUE)))
    spread_b = \(tk) {
      cv = rsmp("cv", folds = 5L); cv$instantiate(tk)
      sd(sapply(seq_len(5L), \(k) mean(tk$data(rows = cv$test_set(k))$y == "min")))
    }
    plain_spread = spread_b(t_b)
    t_strat = t_b$clone(deep = TRUE)
    t_strat$set_col_roles("y", roles = c("target", "stratum"))
    stopifnot(spread_b(t_strat) < plain_spread)

    # 2) bootstrap 分析集携带重复行号 → 图学习器在 PipeOp 内断言失败；普通学习器无恙
    stopifnot(length(t_b$row_ids) == n_b)
    rr_bs_plain = resample(t_b, lrn("classif.rpart"), rsmp("bootstrap", repeats = 3L))
    stopifnot(rr_bs_plain$iters == 3L)
    stopifnot(length(rr_bs_plain$resampling$train_set(1L)) == n_b)
    stopifnot(length(unique(rr_bs_plain$resampling$train_set(1L))) < n_b)
    stopifnot(length(rr_bs_plain$resampling$test_set(1L)) < n_b)
    stopifnot(errored_b(resample(t_b, (po("scale") %>>% lrn("classif.rpart")) |> as_learner(),
      rsmp("bootstrap", repeats = 3L))))

    # 3) 封装/兜底只能走 $encapsulate() 方法；fallback 形参必填；字段与 active binding 只读
    gl_e = (po("scale") %>>% lrn("classif.rpart")) |> as_learner()
    stopifnot(errored_b(gl_e$encapsulate("evaluate")))
    stopifnot(errored_b({gl_e$encapsulation = c(train = "evaluate", predict = "evaluate")}))
    stopifnot(errored_b({gl_e$fallback = lrn("classif.featureless")}))
    stopifnot(errored_b(lrn("classif.rpart", fallback = lrn("classif.featureless"))))
    stopifnot(default_fallback(lrn("classif.rpart"))$id == "classif.featureless")
    stopifnot(default_fallback(lrn("regr.lm"))$id == "regr.featureless")
    gl_e$encapsulate("evaluate", default_fallback(lrn("classif.rpart")))
    stopifnot(identical(names(gl_e$encapsulation), c("train", "predict")))
    stopifnot(gl_e$fallback$id == "classif.featureless")
    rr_enc = resample(t_b, gl_e, rsmp("bootstrap", repeats = 5L))
    stopifnot(rr_enc$iters == 5L)                       # 兜底后全部折完成
    stopifnot(nrow(rr_enc$errors) == 5L)                # 但每折都捕获到错误，记录在此
    stopifnot(identical(names(rr_enc$errors), c("iteration", "condition")))
    stopifnot(is.null(rr_enc$n_resample_iterations))    # 不存在的访问器静默给 NULL
    stopifnot(!("aggregate" %in% names(formals(mlr3::ResampleResult$public_methods$score))))
    stopifnot(nrow(rr_enc$score(msr("classif.ce"))) == 5L)
    stopifnot(is.numeric(rr_enc$aggregate(msr("classif.ce"))))

    # 4) set_threads 形参是 (x, n, ...)；写错名字 = 静默设满核
    l_th = lrn("classif.ranger"); l_bad = lrn("classif.ranger")
    stopifnot("num.threads" %in% l_th$param_set$ids(tags = "threads"))
    set_threads(l_th, n = 1L)
    stopifnot(identical(as.integer(l_th$param_set$values$num.threads), 1L))
    set_threads(l_bad, nthreads = 1L)
    ncores_b = as.integer(future::availableCores())
    stopifnot(identical(as.integer(l_bad$param_set$values$num.threads), ncores_b))
    if (ncores_b > 1L) stopifnot(as.integer(l_bad$param_set$values$num.threads) != 1L)  # 单核机器上两者重合，跳过

    # 5) 资源探测：availableCores 只报额度；future 没有 availableMemory()，memory.limit() 在 Windows 是 Inf
    stopifnot(!("availableMemory" %in% getNamespaceExports("future")))
    stopifnot(all(c("availableCores", "availableWorkers") %in% getNamespaceExports("future")))
    if (requireNamespace("ps", quietly = TRUE)) {
      m = ps::ps_system_memory()
      stopifnot(all(c("total", "avail", "percent") %in% names(m)), m$total > 0, m$avail < m$total)
    }
    # memory.limit() 已不再支持（实测告警且只返回 Inf），不是可用的内存信号
    if (.Platform$OS.type == "windows") {
      ml_warned = FALSE
      ml_val = withCallingHandlers(memory.limit(),
        warning = \(w) { ml_warned <<- TRUE; invokeRestart("muffleWarning") })
      stopifnot(ml_warned, is.infinite(ml_val))
    }

    TRUE
  }),

  ## 文档口径回钉：numeric.md 的行规范化、SKILL.md 的依赖包提示、
  ## advanced-workflows.md §5 的 validate = "test"「静默泄露」说法
  run_case("文档口径·spatialsign 归属 / 依赖包 / validate='test' 静默", {
    set.seed(4817)
    # 1) spatialsign 属 mlr3pipelines 本体（不是 mlr3spatial 之类扩展），默认作用于全部列
    sp_def = mlr_pipeops$get("spatialsign")
    stopifnot("mlr3pipelines" %in% unlist(sp_def$packages))
    stopifnot("PipeOpSpatialSign" %in% ls(asNamespace("mlr3pipelines")))
    d_sp = data.table(y = factor(rep(c("a", "b"), each = 20)),
                      pos = runif(40, 0.1, 5), mixed = rnorm(40))
    t_sp = as_task_classif(d_sp, target = "y", positive = "a")
    o_sp = po("spatialsign")$train(list(t_sp))[[1]]
    stopifnot(all(c("pos", "mixed") %in% o_sp$feature_names))      # 含负值的列同样被变换
    m_sp = as.matrix(o_sp$data(cols = c("pos", "mixed")))
    stopifnot(max(abs(sqrt(rowSums(m_sp^2)) - 1)) < 1e-8)          # 行 L2 范数 = 1

    # 2) classif.xgboost 要的是 xgboost 本体（学习器由 mlr3learners 提供），非 mlr3xgboost
    pk_xgb = unlist(lrn("classif.xgboost")$packages)
    stopifnot(all(c("mlr3learners", "xgboost") %in% pk_xgb))
    stopifnot(!("mlr3xgboost" %in% pk_xgb))
    stopifnot("mlr3mbo" %in% unlist(tnr("mbo")$packages))

    # 3) validate = "test" 合法且**不报错**——所以它是静默泄露而非会被拦下的错误
    l_leak = lrn("classif.xgboost", nrounds = 40L, early_stopping_rounds = 5L,
                 eval_metric = "logloss", predict_type = "prob")
    set_validate(l_leak, validate = "test")
    stopifnot(identical(l_leak$validate, "test"))
    rr_leak = resample(t_sp, l_leak, rsmp("cv", folds = 3L))
    stopifnot(nrow(rr_leak$errors) == 0L)
    stopifnot(is.finite(rr_leak$aggregate(msr("classif.auc"))))
    TRUE
  }),
  run_case("文档口径·robustify 图访问器 / 参数 id / 覆盖默认值", {
    set.seed(6103)
    d_rb = data.table(y = factor(rep(c("yes", "no"), each = 30)),
                      x_num = c(rnorm(50), NA, NA, rnorm(8)),
                      x_ch  = sample(c("a", "b", "c"), 60, TRUE),
                      x_ord = ordered(sample(1:3, 60, TRUE)))
    t_rb = as_task_classif(d_rb, target = "y", positive = "yes")
    g_rb = ppl("robustify")
    # 正文说「$edges 是 14 x 4 边表、$param_set$ids() 有 35 个 node.param、$nodes/$pipe 在 Graph 上是 NULL」
    stopifnot(identical(dim(g_rb$edges), c(14L, 4L)))
    stopifnot(length(g_rb$param_set$ids()) == 35L)
    stopifnot(is.null(g_rb$nodes), is.null(g_rb$pipe))
    stopifnot(all(c("featureunion_robustify", "collapsefactors", "encode") %in% unique(unlist(g_rb$edges))))
    # 正文说「$values 已装 28 条默认值（不是空 list）」
    stopifnot(length(g_rb$param_set$values) == 28L)
    # 正文说「按 节点名.参数名 覆盖：encode.method」——必须真能被 GraphLearner 接受并跑通
    stopifnot(all(c("encode.method", "encode.affect_columns") %in% g_rb$param_set$ids()))
    glrn_rb = as_learner(g_rb %>>% lrn("classif.rpart", predict_type = "prob"))
    glrn_rb$param_set$values[["encode.method"]] = "treatment"
    stopifnot(identical(glrn_rb$param_set$values$encode.method, "treatment"))
    glrn_rb$train(t_rb)
    stopifnot(nrow(glrn_rb$predict_newdata(head(d_rb, 5))$data) == 5L)   # 注意：predict 不接受 type= 参数，改预测类型走 lrn(predict_type=)
    TRUE
  })
)

## 汇总
fails = names(results)[results != "PASS" & results != "SKIP"]
skips = names(results)[results == "SKIP"]
cat(sprintf("\n=== 汇总：%d/%d PASS", sum(results == "PASS"), length(results)))
if (length(skips) > 0) cat(sprintf("，%d SKIP（%s）", length(skips), paste(skips, collapse = "、")))
cat(" ===\n")

# 计时账：为什么要有——CI 曾经「20 例只跑了 25 秒、退出码 1」，而日志里没有任何时长线索，
# 于是分不清"重用例快速报错"和"真的跑完了"。PASS/FAIL 只说结论，秒数说它有没有真干活。
times = unlist(as.list(envir_times))
ord = order(-times)
cat(sprintf("--- 耗时：合计 %.0fs / 会话墙钟 %.0fs | 最慢 5 例：%s\n", sum(times),
  proc.time()[["elapsed"]] - wall_t0,
  paste0(sprintf("%s=%.1fs", names(times)[ord][1:min(5L, length(times))],
    times[ord][1:min(5L, length(times))]), collapse = ", ")))
fast = times[times < 0.05]
if (length(fast)) cat(sprintf("--- 快到可疑（<0.05s，多半是当场报错或纯探针）：%s\n",
  paste(names(fast), collapse = "、")))

if (length(fails) > 0) {
  for (f in fails) cat("FAIL:", f, "->", results[[f]], "\n")
  quit(status = 1)
}
quit(status = 0)
