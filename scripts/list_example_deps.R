# list_example_deps.R —— 把"示例到底要哪些 R 包"变成可重跑的账，而不是 README 里手抄的清单
#
# 为什么要有这个脚本（2026-09-26 的活体尺事故）：CI 首次上线就在 ubuntu + windows 双平台全红，
# 而本机 `verify_examples.R` 20/20 PASS。对账下来根因是门禁里那份**手抄**的依赖清单漏了 `future`——
# 骨架用例 18 里有一句 `future::availableCores()`，而 `future` 只是 mlr3tuning 的 Suggests，
# 装 mlr3verse 不会带它。手抄清单和示例实际用量之间没有防线，哪天示例多加一个 `pkg::`，
# 门禁就先红给全世界看。现在清单由示例本身算出来。
#
# 用法：
#   Rscript scripts/list_example_deps.R                       # 人类可读报告（本机/排障）
#   Rscript scripts/list_example_deps.R --print-list           # 只打印空格分隔的待装包名
#   Rscript scripts/list_example_deps.R --install              # CI：安装 + 复核，硬缺则退出码 1
#   Rscript scripts/list_example_deps.R --src SKILL.md         # 换扫描对象（默认 scripts/verify_examples.R）
#
# 分类口径：
#   hard   = 示例真的会执行到、且没有 requireNamespace 兜底的包 → 装不上就该红
#   opt    = 示例里被 requireNamespace("pkg") 守卫的包 → 缺失由 verify_examples.R 记 SKIP
#   bundled= 随 R 本体发行（base + recommended），不进安装清单

suppressWarnings(suppressMessages({
  need_ml = requireNamespace("mlr3verse", quietly = TRUE)
}))

args = commandArgs(trailingOnly = TRUE)
flag = \(f) any(args == f)
val = \(f, default) {
  i = which(args == f)
  if (!length(i)) return(default)
  args[i[1] + 1L]
}

src_files = unique(val("--src", "scripts/verify_examples.R"))
src_files = unique(unlist(lapply(src_files, Sys.glob)))
src_files = src_files[file.exists(src_files)]
if (!length(src_files)) stop("没有可扫描的源文件：检查 --src 参数")

# --install 模式下先确保锚点包在位：字典键的后备包要靠 mlr3verse 的字典解析，
# 干净机器（CI）上它还没装，不先装就会算出一份"只含 pkg::/library() 里出现的包"的残缺清单。
if (flag("--install") && !requireNamespace("mlr3verse", quietly = TRUE)) {
  cat("=== 先装锚点包 mlr3verse（字典解析依赖它）===\n")
  install.packages("mlr3verse", Ncpus = 4L)
  need_ml = requireNamespace("mlr3verse", quietly = TRUE)
  if (!need_ml) {
    cat("::error::mlr3verse 安装失败，示例依赖清单无法解析\n")
    quit(status = 1L)
  }
}

src = unlist(lapply(src_files, \(f) readLines(f, warn = FALSE)))

# 随 R 发行，不该出现在安装清单里
bundled = c("base", "compiler", "datasets", "grDevices", "graphics", "methods",
  "parallel", "splines", "stats", "tcltk", "tools", "codetools", "utils")

grab_keys = \(fn) {
  m = unlist(regmatches(src, gregexpr(sprintf("%s\\(\\s*[\"']([^\"']+)[\"']", fn), src)), use.names = FALSE)
  if (!length(m)) return(character(0))
  out = sub(sprintf("^%s\\(\\s*[\"']([^\"']+)[\"'].*", fn), "\\1", m)
  sort(unique(out[nzchar(out)]))
}

# 1) 字典键声明的后备包：lrn/po/msr/rsmp/tnr 走各自字典的 $packages，ppl 走 mlr_graphs
dict_of = c(lrn = "mlr_learners", po = "mlr_pipeops", msr = "mlr_measures",
  rsmp = "mlr_resamplings", tnr = "mlr_tuners", ppl = "mlr_graphs")
dict_pkgs = character(0)
dict_detail = list()
if (need_ml) {
  suppressPackageStartupMessages(library(mlr3verse))
  for (fn in names(dict_of)) {
    keys = grab_keys(fn)
    if (!length(keys)) next
    d = get(dict_of[[fn]])                       # 字典由 mlr3verse 附带，直接取
    pk = vapply(keys, \(k) {
      got = try(d$get(k), silent = TRUE)         # ppl 构造器要实参，取不到就跳过
      if (inherits(got, "try-error")) return("")
      paste(as.character(got$packages), collapse = " ")
    }, character(1))
    dict_detail[[fn]] = setNames(strsplit(pk, " ", fixed = TRUE), keys)
    dict_pkgs = c(dict_pkgs, unlist(dict_detail[[fn]], use.names = FALSE))
  }
}

# 2) 正文里直接写死的 pkg:: 前缀（future:: 就是这么溜进来的）
colon_pkgs = unique(unlist(regmatches(src,
  gregexpr("(?<![A-Za-z0-9._])[A-Za-z][A-Za-z0-9.]*(?=::)", src, perl = TRUE)), use.names = FALSE))

# 3) library()/require() 显式加载的包（mlr3tuningspaces 这类"整包挂载"）
lib_pkgs = unique(unlist(regmatches(src,
  gregexpr("(?:library|require)\\(\\s*[\"']?([A-Za-z][A-Za-z0-9.]*)", src, perl = TRUE)), use.names = FALSE))
lib_pkgs = vapply(unlist(regmatches(src,
  gregexpr("(?:library|require)\\(\\s*[\"']?[A-Za-z][A-Za-z0-9.]*", src, perl = TRUE)), use.names = FALSE),
  \(x) sub("^.*(?:library|require)\\(\\s*[\"']?", "", x), character(1))

# 4) 被 requireNamespace("pkg") 守卫的包 = 可选（缺失由 verify_examples.R 记 SKIP）
guarded = unique(unlist(regmatches(src,
  gregexpr("(?<=requireNamespace\\([\"'])([A-Za-z][A-Za-z0-9.]*)(?=[\"'])", src, perl = TRUE))))

need = sort(unique(c(dict_pkgs, colon_pkgs, lib_pkgs)))
need = setdiff(need, bundled)
need = need[nzchar(need)]
hard = setdiff(need, guarded)
opt = intersect(need, guarded)
missing = need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
missing_hard = setdiff(missing, guarded)

if (flag("--print-list")) {
  cat(paste(need, collapse = " "), "\n")
  quit(status = 0L)
}

cat("=== 扫描对象 ===\n"); cat(paste(" ", src_files), sep = "\n")
cat("\n=== 字典键 -> 后备包 ===\n")
for (fn in names(dict_detail)) {
  det = dict_detail[[fn]]
  for (k in names(det)) cat(sprintf("  %-5s %-24s -> %s\n", fn, k, paste(det[[k]], collapse = ", ")))
}
cat("\n=== 正文 pkg:: 直接引用 ===\n")
cat(" ", paste(sort(unique(colon_pkgs)), collapse = "  "), "\n")
cat("\n=== library()/require() 显式加载 ===\n")
cat(" ", paste(sort(unique(lib_pkgs)), collapse = "  "), "\n")
cat("\n=== requireNamespace 守卫（缺失记 SKIP）===\n")
cat(" ", paste(opt, collapse = "  "), "\n")
cat(sprintf("\n=== 待装清单（%d 个，已剔除 base/recommended）===\n", length(need)))
cat(paste(need, collapse = " "), "\n")
cat(sprintf("\nhard = %d | opt = %d | 本机缺失 = %s\n", length(hard), length(opt),
  if (length(missing)) paste(missing, collapse = ", ") else "无"))

if (flag("--install")) {
  # 只补缺失的：CI 干净机器上 need 基本全缺，等于全装；本机则不会去动一套已经跑通的库
  # （install.packages 对已装包会尝试升级，可能把刚验证过的环境换掉）
  todo = need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
  cat("\n=== 安装（缺失 ", length(todo), "/", length(need), " 个）===\n")
  if (length(todo)) install.packages(todo, Ncpus = 4L)

  still = need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
  still_hard = setdiff(still, guarded)
  cat("\n装完复核：仍缺失 =", if (length(still)) paste(still, collapse = ", ") else "无", "\n")
  if (length(still_hard)) {
    cat(sprintf("::error::硬依赖安装失败: %s\n", paste(still_hard, collapse = ", ")))
    quit(status = 1L)
  }
  if (length(still)) cat(sprintf("::warning::可选依赖缺失（用例将记 SKIP）: %s\n", paste(still, collapse = ", ")))
  # 环境指纹写成 annotation：CI 的 step summary 在公开 API 里读不到，而"安装步骤 23 秒报成功"
  # 这种可疑结论必须先能公开复核——它到底装没装、装的是哪一版，一眼可见。
  key = intersect(c("mlr3", "mlr3verse", "mlr3pipelines", "mlr3tuning", "mlr3fselect",
    "mlr3mbo", "paradox", "bbotk", "ranger", "xgboost", "e1071", "future", "ps"), need)
  fingerprint = c(
    sprintf("::notice::deps need=%d todo=%d still_missing=%s",
      length(need), length(todo), if (length(still)) paste(still, collapse = ",") else "-"),    sprintf("::notice::R %s | %s", paste(R.version$major, R.version$minor, sep = "."),
      paste(sprintf("%s=%s", key, vapply(key, \(p) tryCatch(
        as.character(packageVersion(p)), error = \(e) "MISSING"), character(1))), collapse = " ")),
    sprintf("::notice::libPaths[1] = %s", .libPaths()[1])
  )
  cat(paste(fingerprint, collapse = "\n"), "\n")
  summary = Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nzchar(summary)) {
    vers = vapply(need, \(p) tryCatch(as.character(packageVersion(p)), error = \(e) "MISSING"), character(1))
    cat("### 示例依赖（由 scripts/list_example_deps.R 从示例本身算出）\n```\n",
      paste0(sprintf("%-20s", names(vers)), vers, collapse = "\n"), "\n```\n",
      file = summary, append = TRUE)
  }
  quit(status = 0L)
}

if (length(missing_hard)) {
  cat("\n::error::以下硬依赖本机未安装，verify_examples.R 会在对应用例直接报错：",
    paste(missing_hard, collapse = ", "), "\n")
  quit(status = 1L)
}
cat("\n[PASS] 示例所需依赖全部就绪\n")
