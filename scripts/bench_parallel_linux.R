#!/usr/bin/env Rscript
# Linux 并行实测：multicore（fork）vs multisession（进程池）vs 串行
# 只跑内置任务，结果以 ::notice:: 注解输出（公开可读，不依赖日志下载权限）
suppressPackageStartupMessages({
  library(mlr3verse)
  library(data.table)
})
lgr::get_logger("mlr3")$set_threshold("warn")
lgr::get_logger("bbotk")$set_threshold("warn")

say = function(...) cat("::notice::", paste0(...), "\n", sep = "")
cores = future::availableCores()
phys = parallel::detectCores(logical = FALSE)
w = as.integer(min(4L, max(1L, cores - 1L)))
say("LINUX_BENCH env cores=", cores, " phys=", phys,
  " workers=", w, " supportsMulticore=", future::supportsMulticore())

set_plan = function(m, w) {
  if (m == "seq") future::plan("sequential") else future::plan(m, workers = w)
}
plan_class = function() class(future::plan())[1]

# ---- A 短拟合：sonar rpart，CV5，10 次评估 ----
t1 = tsk("sonar"); set.seed(123); s1 = partition(t1, ratio = 0.8)
for (m in c("seq", "multisession", "multicore")) {
  set_plan(m, w)
  at = auto_tuner(tnr("random_search"),
    lrn("classif.rpart", predict_type = "prob", cp = to_tune(0, 0.1)),
    rsmp("cv", folds = 5L), msr("classif.auc"), term_evals = 10L)
  set.seed(1); t0 = proc.time()[["elapsed"]]
  at$train(t1, row_ids = s1$train)
  dt = proc.time()[["elapsed"]] - t0
  pc = plan_class()
  future::plan("sequential")
  say("A_short_rpart ", m, "=", sprintf("%.2f", dt), "s plan=", pc,
    " auc=", sprintf("%.5f", at$tuning_result$classif.auc[[1]]))
}

# ---- B 长拟合：spam + robustify + ranger，CV5，6 次评估 ----
t2 = tsk("spam"); set.seed(123); s2 = partition(t2, ratio = 0.8)
for (m in c("seq", "multisession", "multicore")) {
  set_plan(m, w)
  gl = ppl("robustify") %>>% lrn("classif.ranger", predict_type = "prob",
    num.trees = to_tune(p_int(1, 10, trafo = \(x) 10 * x)),
    max.depth = to_tune(3, 6)) |> as_learner()
  at = auto_tuner(tnr("random_search"), gl, rsmp("cv", folds = 5L),
    msr("classif.auc"), term_evals = 6L)
  set.seed(1); t0 = proc.time()[["elapsed"]]
  at$train(t2, row_ids = s2$train)
  dt = proc.time()[["elapsed"]] - t0
  pc = plan_class()
  future::plan("sequential")
  say("B_long_ranger ", m, "=", sprintf("%.2f", dt), "s plan=", pc,
    " auc=", sprintf("%.5f", at$tuning_result$classif.auc[[1]]))
}

say("LINUX_BENCH done")
