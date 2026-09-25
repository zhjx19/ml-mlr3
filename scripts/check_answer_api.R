#!/usr/bin/env Rscript
# 答案 API 存在性体检（幻觉键抓取）
#
# 断言引擎（run_evals.mjs）量的是**纪律**：种子、测试集、图外预处理、并行资源。
# 它抓不到另一种更致命的错误：代码写得像模像样，但 `po("imputehci")` /
# `rsmp("cs")` / `confusionmatrix()` 这些键与函数在 mlr3verse 里根本不存在——
# 一跑就报错。本脚本把回答里所有字典查找的首参逐个对着真实字典探测，
# 把「不存在的键」点名，并附上字典自己的 "Did you mean" 提示。
#
# 用法（参数支持 glob，Windows 的 pwsh 不展开通配符，这里自己展开）：
#   Rscript scripts/check_answer_api.R "references/*.md" examples/replay/skilled-*.md
# 退出码：0 = 无幻觉键；1 = 至少一个幻觉键；2 = 参数或文件问题。

args = commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  cat("用法: Rscript scripts/check_answer_api.R <answer.md|glob> [...]\n")
  quit(status = 2L)
}
args = unique(unlist(lapply(args, Sys.glob)))
args = args[!dir.exists(args)]
if (!length(args)) {
  cat("没有匹配到任何文件（检查通配符）\n")
  quit(status = 2L)
}
missing_file = args[!file.exists(args)]
if (length(missing_file)) {
  cat("文件不存在:", paste(missing_file, collapse = ", "), "\n")
  quit(status = 2L)
}
suppressMessages(library(mlr3verse))

# 每个入口函数 → 查哪个字典。先用 $has() 定性（最可靠，不受构造器必填参数干扰），
# 键不存在时再用 $get() 把字典自己的 "Did you mean" 提示捞出来。
dicts = list(
  lrn  = mlr_learners,
  po   = mlr_pipeops,
  msr  = mlr_measures,
  rsmp = mlr_resamplings,
  tnr  = mlr_tuners,
  tsk  = mlr_tasks
)
# 批量构造器：首参是 c("a", "b")，逐个拆开
batch = list(lrns = "lrn", msrs = "msr")
# ppl() 没有公开字典对象，只能靠报错信息判定（"not found in DictionaryGraph"）
scan_fns = c(names(dicts), "ppl")

# 只扫 ```r 围栏内的行，返回 list(fn, key, line)
extract_calls = function(lines) {
  hits = list()
  in_r = FALSE
  for (i in seq_along(lines)) {
    ln = lines[[i]]
    if (!in_r && grepl("^```\\s*[rR]\\s*$", ln)) { in_r = TRUE; next }
    if (in_r && grepl("^```\\s*$", ln)) { in_r = FALSE; next }
    if (!in_r) next
    for (fn in scan_fns) {
      m = regmatches(ln, gregexpr(paste0("\\b", fn, "\\(\\s*[\"']([^\"']+)[\"']"), ln))[[1]]
      if (!length(m)) next
      for (hit in m) {
        key = sub("^[a-z]+\\(\\s*[\"']", "", hit)
        key = sub("[\"']$", "", key)
        hits[[length(hits) + 1L]] = list(fn = fn, key = key, line = i)
      }
    }
    for (b in names(batch)) {
      m = regmatches(ln, gregexpr(paste0("\\b", b, "\\(\\s*c\\(([^)]*)\\)"), ln))[[1]]
      if (!length(m)) next
      keys = regmatches(m, gregexpr("[\"'][^\"']+[\"']", m))
      for (ks in keys) {
        for (k in ks) {
          hits[[length(hits) + 1L]] = list(fn = batch[[b]], key = gsub("[\"']", "", k), line = i)
        }
      }
    }
  }
  hits
}

probe = function(fn, key) {
  if (fn == "ppl") {
    msg = tryCatch({ppl(key); NA_character_}, error = function(e) conditionMessage(e))
    if (is.na(msg)) return(list(status = "OK", note = ""))
    if (grepl("not found", msg)) {
      return(list(status = "HALLUCINATED", note = first_line(msg)))
    }
    return(list(status = "OK", note = ""))  # 构造器参数问题：键本身存在
  }
  d = dicts[[fn]]
  if (isTRUE(d$has(key))) return(list(status = "OK", note = ""))
  msg = tryCatch({d$get(key); "not found"}, error = function(e) conditionMessage(e))
  list(status = "HALLUCINATED", note = first_line(msg))
}
first_line = function(msg) {
  ln = strsplit(gsub("\n+", "\n", msg), "\n")[[1]]
  hint = grep("Did you mean|Similar entries", ln, value = TRUE)
  paste(sub("^\\s*", "", if (length(hint)) hint else ln[1]), collapse = "; ")
}

total_hall = 0L
total_ok = 0L
for (f in args) {
  lines = readLines(f, warn = FALSE)
  hits = extract_calls(lines)
  cat(sprintf("\n== %s ==\n", basename(f)))
  if (!length(hits)) {
    cat("  (未找到字典调用)\n")
    next
  }
  seen = new.env()
  file_hall = 0L
  file_ok = 0L
  for (h in hits) {
    id = paste0(h$fn, ":", h$key)
    if (!is.null(seen[[id]])) next
    seen[[id]] = TRUE
    res = probe(h$fn, h$key)
    loc = paste0(h$fn, "(\"", h$key, "\")")
    if (res$status == "OK") {
      file_ok = file_ok + 1L
    } else {
      cat(sprintf("  [幻觉] %-24s 第 %-3d 行 —— %s\n", loc, h$line, res$note))
      file_hall = file_hall + 1L
    }
  }
  cat(sprintf("  小计: 键存在 %d | 幻觉 %d\n", file_ok, file_hall))
  total_ok = total_ok + file_ok
  total_hall = total_hall + file_hall
}

cat(sprintf("\n=== 汇总：%d 个唯一字典键 | 幻觉 %d | 存在 %d ===\n",
  total_ok + total_hall, total_hall, total_ok))
if (total_hall > 0L) {
  cat("结论：回答里有 mlr3verse 字典中不存在的键，照抄必报错。改法见 SKILL.md「API 现场校验」。\n")
}
quit(status = if (total_hall > 0L) 1L else 0L)
