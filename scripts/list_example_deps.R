# list_example_deps.R —— 把"示例到底要哪些 R 包"变成可重跑的账，而不是 README 里手抄的清单
#
# 为什么要有这个脚本（2026-09-26 的活体尺事故，同一处先后抓到两个洞）：
# 洞 1：门禁里那份**手抄**清单漏了 `future`——用例 18 有 `future::availableCores()`，而它只是
#        mlr3tuning 的 Suggests，装 mlr3verse 不带。→ 清单改由示例本身算出来。
# 洞 2：清单由"紧跟在 lrn( / po( 后面的字符串"算出来，漏了 `lrns(c("classif.rpart","classif.kknn"))`
#        里的 kknn，也永远算不到 mlr3extralearners（该包没装时它注册的键压根不在字典里，
#        扫字典的脚本无法发现自己缺了它）。→ 见下面 anchor 账 + ctor 行判定。
# 两次都是同一个病：**本机全绿、CI 全红**，差别只在于机器上手动装过什么。
#
# 用法：
#   Rscript scripts/list_example_deps.R                       # 人类可读报告（本机/排障）
#   Rscript scripts/list_example_deps.R --print-list           # 只打印空格分隔的待装包名
#   Rscript scripts/list_example_deps.R --install              # CI：安装 + 复核，硬缺则退出码 1
#   Rscript scripts/list_example_deps.R --src SKILL.md         # 换扫描对象（默认 scripts/verify_examples.R）
#
# 分类口径：
#   anchor = 提供字典本身的包（装了它，字典才枚举得出对应键）→ 无条件先装
#   hard   = 示例真的会执行到、且没有 requireNamespace 兜底的包 → 装不上就该红
#   opt    = 示例里被 requireNamespace("pkg") 守卫的包 → 缺失由 verify_examples.R 记 SKIP
#   bundled= 随 R 本体发行（base + recommended），不进安装清单

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

# ── 锚点账：字典的提供方包，不靠扫描发现（扫描依赖它们先在场）────────────────────
# 锚点分两级，依据是 2026-09-26 的预飞实测（对着 TUNA 的 CRAN 索引逐个查）：
#   硬锚点 = mlr3verse / mlr3learners，CRAN 上就有；装不上 = 这台机器根本没法跑门禁 → 直接红。
#   软锚点 = mlr3extralearners，**不在 CRAN**：CRAN 索引 25158 个包里没有它、包页返回 404，
#     本机那份 DESCRIPTION 的 Repository 字段是 NA、版本号 1.7.0.9000（GitHub 构建的形态）。
#     官方分发通道是 mlr-org 的 r-universe（源索引里有 mlr3extralearners 1.7.0，且带
#     Windows 4.6 二进制）。它缺席只影响它注册的那几个键（classif.lightgbm / regr.lightgbm /
#     classif.catboost），所以装不上 = 相关键记 SKIP，而不是把整个门禁钉红——
#     把"分发通道问题"伪装成"文档有幻觉"，是比红更糟的红灯。
anchor_hard = c("mlr3verse", "mlr3learners")
anchor_soft = "mlr3extralearners"
anchor = c(anchor_hard, anchor_soft)
# 只追加到 repos 末位：CRAN / RSPM 供得上的包照旧走原通道，只有它们没有的才落到 universe。
extra_repos = c(mlorg = "https://mlr-org.r-universe.dev")
installed = \(p) vapply(p, requireNamespace, logical(1), quietly = TRUE)

if (flag("--install")) {
  a_miss = anchor[!installed(anchor)]
  if (length(a_miss)) {
    cat("=== 先装锚点包（字典提供方）:", paste(a_miss, collapse = ", "), "===\n")
    install.packages(a_miss, repos = c(getOption("repos"), extra_repos), Ncpus = 4L)
    a_hard = anchor_hard[!installed(anchor_hard)]
    if (length(a_hard)) {
      cat(sprintf("::error::硬锚点安装失败，字典无法枚举: %s\n", paste(a_hard, collapse = ", ")))
      quit(status = 1L)
    }
    if (!installed(anchor_soft))
      cat(sprintf("::warning::软锚点 %s 未就位（CRAN 无此包，需 r-universe）：它注册的键记 SKIP\n", anchor_soft))
  }
}
# 扫描还没开始前就把"这台机器认领不认领软锚点"记下来，后面算 hard/opt 时要用。
anchor_opt = if (installed(anchor_soft)) character(0) else anchor_soft
need_ml = installed("mlr3verse")

src = unlist(lapply(src_files, \(f) readLines(f, warn = FALSE)))

# 随 R 发行，不该出现在安装清单里
bundled = c("base", "compiler", "datasets", "grDevices", "graphics", "methods",
  "parallel", "splines", "stats", "tcltk", "tools", "codetools", "utils")

# ── 1) 会被真正实例化的键 = 出现在字典构造函数所在**整行**上的字符串 ──────────────
# 为什么按行而不是按"紧跟 fn( 的位置"：`lrns(c("classif.rpart", "classif.kknn"))` 里 kknn 不在
# `lrn(` 后面，按位置扫就漏；漏了就是 CI 上那句 "The following packages could not be loaded: kknn"。
ctor_line_pat = "(^|[^A-Za-z0-9._])(lrns?|msrs?|rsmps?|tnrs?|fss?|tsks?|pos?|ppl|graphs?|fsors?|tnors?)\\("
ctor_src = src[vapply(src, \(l) grepl(ctor_line_pat, l, perl = TRUE), logical(1))]
quoted = \(x) unique(gsub("[\"']", "", unlist(regmatches(x,
  gregexpr("[\"']([A-Za-z][A-Za-z0-9._]*)[\"']", x, perl = TRUE)), use.names = FALSE)))
dict_keys = setdiff(quoted(ctor_src), bundled)

# 键 -> 它声明的后备包。后端没装时 $get() 只发 warning（"Package 'dbarts' required but not
# installed"）但包名照样读得到，所以这里 muffling 警告而不是放弃解析。
dict_names = c("mlr_learners", "mlr_pipeops", "mlr_measures", "mlr_resamplings",
  "mlr_tuners", "mlr_graphs", "mlr_fselectors", "mlr_tasks")
dict_pkgs = character(0)
dict_detail = list()
if (need_ml) {
  suppressPackageStartupMessages(library(mlr3verse))
  for (dn in dict_names) {
    # 注意：字典是 R6 环境对象，`exists(dn, mode = "list")` 会把它判成"不存在"而全体跳过——
    # 那样清单会静默退化成只剩 pkg::/library() 那条路，正是本脚本要防的病。用默认 mode。
    if (!exists(dn)) next
    d = get(dn)
    hit = Filter(\(k) isTRUE(try(d$has(k), silent = TRUE)), dict_keys)
    if (!length(hit)) next
    pk = vapply(hit, \(k) {
      got = withCallingHandlers(try(d$get(k), silent = TRUE),
        warning = \(w) invokeRestart("muffleWarning"))
      if (inherits(got, "try-error")) return("")          # 图/个别 PipeOp 构造器要实参：只记账不取包
      paste(as.character(got$packages), collapse = " ")
    }, character(1))
    dict_detail[[dn]] = setNames(strsplit(pk, " ", fixed = TRUE), hit)
    dict_pkgs = c(dict_pkgs, unlist(dict_detail[[dn]], use.names = FALSE))
  }
}

# 自检：有键可解析却一个都没解析出来 = 字典枚举静默失败，清单必然残缺 → 直接红，不出清单。
# 这条钉子来自今天的真事故（mode="list" 让八个字典全被跳过，清单从 17 个悄悄掉到 9 个）。
if (need_ml && length(dict_keys) && !any(nzchar(dict_pkgs))) {
  cat(sprintf("::error::扫到 %d 个候选键却解析出 0 个后备包：字典枚举失败，清单不可信\n", length(dict_keys)))
  quit(status = 1L)
}

# ── 2) 正文里直接写死的 pkg:: 前缀（洞 1 的 future:: 就是这么溜进来的）──────────────
colon_pkgs = unique(unlist(regmatches(src,
  gregexpr("(?<![A-Za-z0-9._])[A-Za-z][A-Za-z0-9.]*(?=::)", src, perl = TRUE)), use.names = FALSE))

# ── 3) library()/require() 显式加载的包（mlr3tuningspaces 这类"整包挂载"）───────────
lib_pkgs = vapply(unlist(regmatches(src,
  gregexpr("(?:library|require)\\(\\s*[\"']?[A-Za-z][A-Za-z0-9.]*", src, perl = TRUE)), use.names = FALSE),
  \(x) sub("^.*(?:library|require)\\(\\s*[\"']?", "", x), character(1))

# ── 4) 被 requireNamespace("pkg") 守卫的包 = 可选（缺失由 verify_examples.R 记 SKIP）──
guarded = unique(unlist(regmatches(src,
  gregexpr("(?<=requireNamespace\\([\"'])([A-Za-z][A-Za-z0-9.]*)(?=[\"'])", src, perl = TRUE))))

need = sort(unique(c(anchor, dict_pkgs, colon_pkgs, lib_pkgs)))
need = setdiff(need, bundled)
need = need[nzchar(need)]
# 可选 = 源码里被 requireNamespace 守卫的 + 本机未就位的软锚点（它对应的键用例会自己 SKIP）
opt = union(intersect(need, guarded), anchor_opt)
hard = setdiff(need, opt)
missing = need[!installed(need)]
missing_hard = setdiff(missing, opt)

if (flag("--print-list")) {
  cat(paste(need, collapse = " "), "\n")
  quit(status = 0L)
}

cat("=== 扫描对象 ===\n"); cat(paste(" ", src_files), sep = "\n")
cat(sprintf("\n=== 锚点包（字典提供方，无条件先装）===\n  硬（CRAN 可得）: %s\n  软（CRAN 无，走 %s）: %s%s\n",
  paste(anchor_hard, collapse = "  "), extra_repos[1], anchor_soft,
  if (length(anchor_opt)) "  ← 本机未就位，相关键记 SKIP" else ""))
cat("\n=== 构造函数行上的键 -> 后备包 ===\n")
for (dn in names(dict_detail)) {
  det = dict_detail[[dn]]
  for (k in names(det)) cat(sprintf("  %-16s %-26s -> %s\n", dn, k, paste(det[[k]], collapse = ", ")))
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

# ── 预飞：清单算出来了，还得问一句"CI 那份仓库快照里到底有没有它" ──────────────────
# 为什么要这一条：软锚点那场事故（mlr3extralearners 不在 CRAN）在本机永远看不出来——
# 本机那份是当初从 GitHub 装的，DESCRIPTION 里 Repository 字段直接是 NA。
# 用法：--mirror [--repos <CRAN 镜像 URL>]（本机默认 @CRAN@ 会去撞 cloud.r-project.org，
# 国内建议显式给镜像；CI 上不给也一样，runner 就贴在 CRAN / RSPM 旁边）。
if (flag("--mirror")) {
  base_repos = val("--repos", "https://cloud.r-project.org")
  idx = \(u) tryCatch(rownames(available.packages(repos = u, type = "source")), error = \(e) NULL)
  cat("\n=== 镜像可得性预飞 ===\n")
  av_base = idx(base_repos)
  av_uni = idx(extra_repos[[1]])
  if (is.null(av_base) && is.null(av_uni)) {
    cat(sprintf("::warning::两个仓库索引都取不到（%s / %s），本轮不判可得性\n", base_repos, extra_repos[[1]]))
    quit(status = 0L)
  }
  cat(sprintf("  索引规模：主仓库 %s | mlorg r-universe %s\n",
    if (is.null(av_base)) "取不到" else length(av_base),
    if (is.null(av_uni)) "取不到" else length(av_uni)))
  nowhere = need[!(need %in% av_base) & !(need %in% av_uni)]
  for (p in need) {
    from = if (p %in% av_base) base_repos else if (p %in% av_uni) extra_repos[[1]] else "两边都没有"
    cat(sprintf("  %-22s <- %s\n", p, from))
  }
  only_uni = need[!(need %in% av_base) & (need %in% av_uni)]
  cat(sprintf("\n  只存在于非 CRAN 通道的包：%s\n", if (length(only_uni)) paste(only_uni, collapse = ", ") else "无"))
  # Windows job 那边要看有没有预编译二进制：没有编译链的 runner 上，source-only 会当场失败
  if (length(only_uni)) {
    # R 的 Windows 二进制目录按 "主.次" 分（4.6.1 → 4.6），R.version$minor 是 "6.1"，只取第一段。
    # 这个仓库的二进制索引直接放在 contrib 层（没有 src/contrib 子目录），所以读文件而不是 available.packages。
    win_url = sprintf("%s/bin/windows/contrib/%s.%s/PACKAGES", extra_repos[[1]], R.version$major,
      sub("\\..*$", "", R.version$minor))
    win_txt = tryCatch(readLines(win_url, warn = FALSE), error = \(e) character(0))
    win_pkgs = sub("^Package: ", "", grep("^Package: ", win_txt, value = TRUE))
    cat(sprintf("  Windows 二进制索引（%s，读到 %d 个）：%s\n", win_url, length(win_pkgs),
      paste(sprintf("%s=%s", only_uni, ifelse(only_uni %in% win_pkgs, "有", "无（要当场编译）")), collapse = " ")))
  }
  if (length(nowhere)) {
    cat(sprintf("\n::error::以下包在两个仓库里都查不到，门禁不可能装上它: %s\n", paste(nowhere, collapse = ", ")))
    quit(status = 1L)
  }
  cat("\n[PASS] 清单里的每个包都有明确来源\n")
  quit(status = 0L)
}

if (flag("--install")) {
  # 只补缺失的：CI 干净机器上 need 基本全缺，等于全装；本机则不会去动一套已经跑通的库
  # （install.packages 对已装包会尝试升级，可能把刚验证过的环境换掉）
  todo = need[!installed(need)]
  cat("\n=== 安装（缺失 ", length(todo), "/", length(need), " 个）===\n")
  if (length(todo)) install.packages(todo, repos = c(getOption("repos"), extra_repos), Ncpus = 4L)

  still = need[!installed(need)]
  # 装完再认一次软锚点：CI 上它多半是这一步才从 r-universe 落下来的
  still_opt = union(guarded, if (installed(anchor_soft)) character(0) else anchor_soft)
  still_hard = setdiff(still, still_opt)
  cat("\n装完复核：仍缺失 =", if (length(still)) paste(still, collapse = ", ") else "无", "\n")
  if (length(still_hard)) {
    cat(sprintf("::error::硬依赖安装失败: %s\n", paste(still_hard, collapse = ", ")))
    quit(status = 1L)
  }
  if (length(still)) cat(sprintf("::warning::可选依赖缺失（用例将记 SKIP）: %s\n", paste(still, collapse = ", ")))

  # 环境指纹写成 annotation：step summary 在公开 API 里读不到，而"安装步骤 19 秒报成功"这种
  # 结论必须能被匿名读者复核——它到底装没装、装的是哪一版、装进了哪条 libPath。
  key = intersect(c("mlr3", "mlr3verse", "mlr3learners", "mlr3extralearners", "mlr3pipelines",
    "mlr3tuning", "mlr3mbo", "bbotk", "ranger", "xgboost", "kknn", "e1071", "future", "ps"), need)
  vers = vapply(key, \(p) tryCatch(as.character(packageVersion(p)), error = \(e) "MISSING"), character(1))
  cat(paste(c(
    sprintf("::notice::deps need=%d todo=%d still_missing=%s",
      length(need), length(todo), if (length(still)) paste(still, collapse = ",") else "-"),
    sprintf("::notice::R %s | %s", paste(R.version$major, R.version$minor, sep = "."),
      paste(sprintf("%s=%s", key, vers), collapse = " ")),
    sprintf("::notice::libPaths[1] = %s", .libPaths()[1]),
    # 软锚点的来源必须留痕：CI 上 mlr3extralearners 只可能从 r-universe 落下来，
    # 没有这条，"它装了"和"它从哪装的"就又被当成同一件事。
    sprintf("::notice::repos = %s | soft_anchor %s = %s",
      paste(names(getOption("repos")), collapse = "+"), anchor_soft,
      if (installed(anchor_soft)) as.character(packageVersion(anchor_soft)) else "MISSING(相关键 SKIP)")
  ), collapse = "\n"), "\n")

  summary = Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nzchar(summary)) {
    all_v = vapply(need, \(p) tryCatch(as.character(packageVersion(p)), error = \(e) "MISSING"), character(1))
    cat("### 示例依赖（由 scripts/list_example_deps.R 从示例本身算出）\n```\n",
      paste0(sprintf("%-20s", names(all_v)), all_v, collapse = "\n"), "\n```\n",
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
