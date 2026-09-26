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
# 但先把 @CRAN@ 占位落实成真实 URL——非交互的 CI 里带着占位符去问镜像会当场卡住/乱挑，
# 而这里恰恰是"本地默认 @CRAN@、CI 是 RSPM"两边都要跑得通的脚本。
universe_repos = c(mlorg = "https://mlr-org.r-universe.dev")
base_repos = local({
  r = getOption("repos")
  if (any(grepl("@CRAN@", r))) r[grepl("@CRAN@", r)] = "https://cloud.r-project.org"
  r
})
repos_all = c(base_repos, universe_repos)
installed = \(p) vapply(p, requireNamespace, logical(1), quietly = TRUE)

# ── 安装必须自带病因 ────────────────────────────────────────────────────────────
# 为什么：2026-09-26 的 ubuntu job 红在 "硬依赖安装失败: kknn"，而真正的编译错误一行都没被
# 公开通道读到——install.packages 的输出只写 stdout，落在 Actions 日志里，匿名读者只能看到
# annotations（/logs 要仓库权限，403）。于是"红灯自带病因"这条纪律在门禁自己的安装步骤上失效了。
# 做法：安装走子进程，输出用 system2(stdout=TRUE, stderr=TRUE) 收成字符向量再落盘；
# 失败时把日志尾部 + 传递依赖缺口贴成 ::error::。
# 两条实测坑（2026-09-26 Windows）：① R.home("bin") 在 Windows 上是 bin/x64，那里只有
# Rscript.exe——不补 .exe 就是 rc=5、日志空；② stdout=/stderr= 指到同一个文件在这条路上
# 拿不到内容，所以改成捕获式，自己 writeLines。
# 子进程必须装进**父会话看得见**的库目录，否则装成功而父会话 requireNamespace 仍是 FALSE——
# 那是假红。库目录不靠环境变量传（system2 的 env= 在 Windows 上把整条命令拼歪了，实测 rc=5），
# 而是写成一个文件、子进程自己 readLines 后 .libPaths() 覆盖——顺带避开 Windows 路径的转义坑。
install_logs = character(0)
install_rc = integer(0)
rscript_bin = file.path(R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
# 临时目录放产物：直接写在仓库工作目录里，本机跑一次就多出一堆 install_*.log 未跟踪文件
artifact_dir = tempfile("mlr3-deps-")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
# deparse 对长向量会折行，返回**字符向量**；直接塞进 sprintf 会让一条语句被拆成两行、
# 语法当场碎掉（red 模拟实测：repos = c(CRAN=..., mlorg=...) 变成两条不完整语句）。
# 所以一律压成单行。
dep1 = function(x) paste(deparse(x), collapse = " ")

install_logged = function(pkgs, tag) {
  logf = file.path(artifact_dir, sprintf("install_%s.log", tag))
  exprf = file.path(artifact_dir, sprintf("install_%s.R", tag))
  libf = file.path(artifact_dir, sprintf("install_%s.lib", tag))
  writeLines(.libPaths(), libf)
  fwd = function(f) normalizePath(f, winslash = "/", mustWork = FALSE)
  writeLines(c(
    sprintf('libf = "%s"', fwd(libf)),
    '.libPaths(readLines(libf))',
    # 子进程到底装进了哪个目录、用的哪套仓库，必须由它自己报出来："装了但父会话看不见"
    # 是这套诊断最容易自欺的形态，而 install.packages 的那句 Installing package into 就是回执。
    'writeLines(paste("TARGET_LIB:", .libPaths()[1]))',
    # 两条都要：getOption("repos") 是 runner 的站点配置（本机默认是占位符 @CRAN@），
    # 而真正传给 install.packages 的是父会话算出来的那套。只报前者，在 CI 上会读成
    # "仓库是 @CRAN@"这种压根不存在的东西；只报后者，就看不出 runner 本身配了什么。
    sprintf('writeLines(paste("REPOS_USED:", getOption("repos"), "| 实际请求:", %s))', dep1(repos_all)),
    sprintf('install.packages(%s, repos = %s, Ncpus = 4L)', dep1(pkgs), dep1(repos_all)),
    'quit(status = 0L)'
  ), exprf)
  # 生成的子进程脚本必须先能 parse：不检查的话，语法碎掉表现为"包全都装不上"，
  # 而日志里只留一句 unexpected symbol——病因会被误读成网络或仓库问题。
  stopifnot(!inherits(try(parse(exprf), silent = TRUE), "try-error"))
  # 不用 --vanilla：它会连 .Rprofile / .Renviron 一起跳过，而 runner 的 P3M/RSPM 二进制通道
  # 正是靠站点配置里的仓库与 User-Agent 生效的——跳掉它等于在 ubuntu 上强制退回纯源码编译。
  # 只关掉 --save/--restore，库目录靠上面那句 .libPaths() 显式覆盖。
  out = system2(rscript_bin, c("--no-save", "--no-restore", shQuote(fwd(exprf))),
    stdout = TRUE, stderr = TRUE)
  writeLines(as.character(out), logf)
  raw = attr(out, "status")   # system2 只在非零退出时挂 status（实测 Windows 成功时是 NULL）
  st = if (is.null(raw) || length(raw) == 0L) 0L else as.integer(raw)
  if (is.na(st)) st = -1L
  # 一条输出都没有 = 子进程压根没跑起来（今天 Windows 上 rc=5 就是这个形态），
  # 这时"退出码 0"是假的，标成 -1 让红灯带着这条一起出来。
  if (st == 0L && !length(out)) st = -1L
  install_logs <<- c(install_logs, setNames(logf, tag))
  install_rc <<- c(install_rc, setNames(st, tag))
  tgt = grep("^TARGET_LIB:", out, value = TRUE)
  cat(sprintf("  [%s] rc = %s | 日志 %d 行 | %s\n", tag, st, length(out),
    if (length(tgt)) tgt[1] else "TARGET_LIB 缺失（子进程可能没起来）"))
  invisible(st)
}

read_log = function() {
  if (!length(install_logs)) return(character(0))   # lapply(list()) 返回 list()，unlist 后是 NULL
  as.character(unlist(lapply(install_logs, function(f)
    if (file.exists(f)) readLines(f, warn = FALSE) else character(0)), use.names = FALSE))
}

# 注解里的多行必须用 %0A（工作流命令按行解析，裸换行会把一条诊断劈成 N 条）
annotate = function(level, title, lines, keep = 30, max = 2600) {
  lines = as.character(lines)
  if (length(lines) > keep) lines = lines[(length(lines) - keep + 1L):length(lines)]
  txt = paste(c(title, lines), collapse = "%0A")
  if (nchar(txt) > max) txt = paste0("…(截断)", substring(txt, nchar(txt) - max))
  cat(sprintf("::%s::%s\n", level, txt), sep = "")
}

# 某个包在日志里出现的最后一段。口径必须两种风味都认（2026-09-26 实测）：
#   Linux/源码：  "* installing *source* package 'kknn' ..." ... "* DONE (kknn)"
#   Windows/二进制：没有 "* installing" 行，只有 "package 'kknn' successfully unpacked and MD5 sums checked"
# 只按第一种写的话，Windows 上的失败日志会被解析成"这个包压根没出现在日志里"——那是假病因。
around = function(lines, i, n) {
  if (!length(i)) return(character(0))
  lines[max(1L, i - n):min(length(lines), i + n)]
}

pkg_block = function(lines, pkg, n = 12L) {
  tag = sprintf("package '%s'", pkg)
  hit = which(vapply(lines, function(l) grepl(tag, l, fixed = TRUE), logical(1)))
  around(lines, if (length(hit)) max(hit) else integer(0), n)
}

# 比"按包名捞段"更兜底的一招：直接把报错行连上下文一起端出来，不依赖任何行的格式。
err_pat = "ERROR:|^ERROR|fatal error|non-zero exit status|had a non-zero|not available for this version|installation of package .* had"
err_window = function(lines, half = 8L, max_lines = 60L) {
  hit = grep(err_pat, lines, perl = TRUE)
  if (!length(hit)) return(character(0))
  idx = sort(unique(as.integer(unlist(lapply(hit, function(i)
    max(1L, i - half):min(length(lines), i + half))))))
  if (length(idx) > max_lines) idx = idx[(length(idx) - max_lines + 1L):length(idx)]
  sprintf("%4d| %s", idx, lines[idx])   # 带行号：日志本身在 Actions 里，读者要能对上位置
}

# 装完还缺的包，真正的凶手常常在**传递依赖**里：kknn 只是"没装上"的那个，
# 而 igraph 才是"编译失败"的那个——它不在 need 里，不额外算就永远不会被点名。
closure_missing = function(pkgs) {
  # 依赖口径写在 package_dependencies 的 which 里，不写在 available.packages 的 filters 里
  # （filters = c("Depends","Imports","LinkingTo") 实测直接报 invalid 'filters' argument，
  #  而这里外面套了 tryCatch(NULL)——静默返回"什么都不缺"，正是要防的那种假病因）。
  db = tryCatch(available.packages(repos = repos_all), error = function(e) NULL)
  if (is.null(db)) {
    annotate("warning", "取不到仓库索引，传递依赖缺口这一栏无法判定", character(0), keep = 0)
    return(character(0))
  }
  deps = tools::package_dependencies(pkgs, db = db, recursive = TRUE,
    which = c("Depends", "Imports", "LinkingTo"))
  cl = unique(unlist(deps, use.names = FALSE))
  cl = setdiff(cl, c(bundled, "R", pkgs))
  inst = rownames(installed.packages())
  sort(setdiff(cl, inst))
}

if (flag("--install")) {
  a_miss = anchor[!installed(anchor)]
  if (length(a_miss)) {
    cat("=== 先装锚点包（字典提供方）:", paste(a_miss, collapse = ", "), "===\n")
    install_logged(a_miss, "anchor")
    a_hard = anchor_hard[!installed(anchor_hard)]
    if (length(a_hard)) {
      lg = read_log()
      annotate("error", sprintf("硬锚点安装失败，字典无法枚举: %s | 报错上下文", paste(a_hard, collapse = ", ")),
        if (length(err_window(lg))) err_window(lg) else lg, keep = 40L)
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
  paste(anchor_hard, collapse = "  "), universe_repos[1], anchor_soft,
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
  mirror_base = val("--repos", base_repos[[1]])
  idx = \(u) tryCatch(rownames(available.packages(repos = u, type = "source")), error = \(e) NULL)
  cat("\n=== 镜像可得性预飞 ===\n")
  av_base = idx(mirror_base)
  av_uni = idx(universe_repos[[1]])
  if (is.null(av_base) && is.null(av_uni)) {
    cat(sprintf("::warning::两个仓库索引都取不到（%s / %s），本轮不判可得性\n", mirror_base, universe_repos[[1]]))
    quit(status = 0L)
  }
  cat(sprintf("  索引规模：主仓库 %s → %s | mlorg r-universe → %s\n", mirror_base,
    if (is.null(av_base)) "取不到" else sprintf("%d 个包", length(av_base)),
    if (is.null(av_uni)) "取不到" else sprintf("%d 个包", length(av_uni))))
  nowhere = need[!(need %in% av_base) & !(need %in% av_uni)]
  for (p in need) {
    from = if (p %in% av_base) mirror_base else if (p %in% av_uni) universe_repos[[1]] else "两边都没有"
    cat(sprintf("  %-22s <- %s\n", p, from))
  }
  only_uni = need[!(need %in% av_base) & (need %in% av_uni)]
  cat(sprintf("\n  只存在于非 CRAN 通道的包：%s\n", if (length(only_uni)) paste(only_uni, collapse = ", ") else "无"))
  # Windows job 那边要看有没有预编译二进制：没有编译链的 runner 上，source-only 会当场失败
  if (length(only_uni)) {
    # R 的 Windows 二进制目录按 "主.次" 分（4.6.1 → 4.6），R.version$minor 是 "6.1"，只取第一段。
    # 这个仓库的二进制索引直接放在 contrib 层（没有 src/contrib 子目录），所以读文件而不是 available.packages。
    win_url = sprintf("%s/bin/windows/contrib/%s.%s/PACKAGES", universe_repos[[1]], R.version$major,
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
  if (length(todo)) install_logged(todo, "deps")

  # 第二轮只补第一轮没装上的那几个。为什么值得多这一遍：ubuntu 那次红在 kknn，而它 1.4.1
  # 在 CRAN 自己的 r-patched/r-devel debian-gcc 上全是 OK，165 秒的步骤也不够编译它的依赖
  # igraph——"确定性装不上"和"这一次没装上"两种病因，公开通道根本分不出来。重试一次就能分：
  # 补上了 = 瞬时故障（记进 notice，别让下一次红继续猜），仍缺 = 确定性的，日志里必有原文。
  still0 = need[!installed(need)]
  still0_hard = setdiff(still0, union(guarded, if (installed(anchor_soft)) character(0) else anchor_soft))
  if (length(still0_hard)) {
    cat("\n=== 第二轮（只补缺的 ", length(still0_hard), " 个）===\n", sep = "")
    install_logged(still0_hard, "retry")
  }

  # 装没装成之外，还要说清"从哪个通道、以什么形态装的"：ubuntu 上如果 source 段占了绝大多数，
  # 说明 P3M/RSPM 的二进制没被用上，一次 igraph 级编译就足够把步骤拖爆。
  # 三种形态分开数（实测口径）：Linux 源码 "* installing *source* package '...'"、
  # RSPM 二进制 "* installing *binary* package '...'"、Windows 二进制 "package '...' successfully unpacked"。
  lg = read_log()
  n_src = sum(startsWith(lg, "* installing *source* package '"))
  n_bin = sum(startsWith(lg, "* installing *binary* package '"))
  n_win = sum(vapply(lg, function(l) grepl("successfully unpacked", l, fixed = TRUE), logical(1)))
  cat(sprintf("::notice::install log lines=%d source=%d binary=%d win_unpacked=%d rc=%s\n",
    length(lg), n_src, n_bin, n_win, paste(sprintf("%s:%s", names(install_rc), install_rc), collapse = " ")))
  # 子进程的回执（装进了哪个库、用的哪套仓库）单独成条：它是区分"装到别处去了"和
  # "真的装不上"的唯一证据，混在形态计数里就没人会去读。
  tgt = grep("^TARGET_LIB:|^REPOS_USED:", lg, value = TRUE)
  if (length(tgt)) annotate("notice", "安装子进程回执", tgt, keep = 6L)

  still = need[!installed(need)]
  # 装完再认一次软锚点：CI 上它多半是这一步才从 r-universe 落下来的
  still_opt = union(guarded, if (installed(anchor_soft)) character(0) else anchor_soft)
  still_hard = setdiff(still, still_opt)
  fixed_by_retry = setdiff(still0_hard, still_hard)
  if (length(fixed_by_retry))
    annotate("warning", sprintf("重试才装上的包（= 第一轮是瞬时故障，不是装不上）: %s",
      paste(fixed_by_retry, collapse = ", ")), character(0), keep = 0)
  cat("\n装完复核：仍缺失 =", if (length(still)) paste(still, collapse = ", ") else "无", "\n")
  if (length(still_hard)) {
    # 头条必须先给"哪些硬依赖没装上"：下面那些上下文再详细，读者也要第一眼看到结论
    annotate("error", sprintf("硬依赖安装失败: %s", paste(still_hard, collapse = ", ")),
      character(0), keep = 0)
    # 先点名传递依赖：need 里"没装上"的包往往只是受害者，日志里真正报错的是它的依赖
    cm = closure_missing(still_hard)
    if (length(cm))
      annotate("error", sprintf("硬依赖 %s 的传递依赖里还缺: %s（真凶多半在这里）",
        paste(still_hard, collapse = ", "), paste(cm, collapse = ", ")), character(0), keep = 0)
    for (p in union(still_hard, cm)) {
      blk = pkg_block(lg, p)
      if (length(blk)) { annotate("error", sprintf("[%s] 安装段尾部：", p), blk); next }
      # 该包没有自己的安装段 = 根本没轮到它（通常是被上面某段的 ERROR 连坐）
      annotate("warning", sprintf("[%s] 日志里没有它的安装段（未轮到安装）", p), character(0), keep = 0)
    }
    ew = err_window(lg)
    if (length(ew)) annotate("error", "安装日志里的报错行（连上下文）：", ew, keep = 60L)
    else annotate("warning", "日志里没有匹配到任何报错行：失败形态不是编译错，看下面的 rc/形态计数",
      character(0), keep = 0)
    quit(status = 1L)
  }
  if (length(still)) cat(sprintf("::warning::可选依赖缺失（用例将记 SKIP）: %s\n", paste(still, collapse = ", ")))

  # 环境指纹写成 annotation：step summary 在公开 API 里读不到，而"安装步骤 19 秒报成功"这种
  # 结论必须能被匿名读者复核——它到底装没装、装的是哪一版、装进了哪条 libPath。
  key = intersect(c("mlr3", "mlr3verse", "mlr3learners", "mlr3extralearners", "mlr3pipelines",
    "mlr3tuning", "mlr3mbo", "bbotk", "ranger", "xgboost", "kknn", "e1071", "future", "ps"), need)
  vers = vapply(key, \(p) tryCatch(as.character(packageVersion(p)), error = \(e) "MISSING"), character(1))
  # 通道纯度自检：mlr-org 的 universe 里 bbotk / mlr3 / mlr3misc / mlr3tuning 等也在（而且是 .9xxx
  # 开发版）。repos 把 CRAN/RSPM 摆在前面就是为了不让它们抢走同名包——"应该抢不走"和"实测没抢走"
  # 是两件事：门禁要是测了开发版，报出来的通过率就属于另一套代码，而 annotation 看起来仍旧全绿。
  # 名单不与 need 求交：paradox / mlr3misc 这类是传递依赖，不在清单里但同样会被 universe 抢走。
  core = c("mlr3", "mlr3verse", "mlr3learners", "mlr3pipelines", "mlr3tuning", "mlr3fselect",
    "mlr3mbo", "bbotk", "paradox", "mlr3misc")
  core_v = vapply(core, \(p) tryCatch(as.character(packageVersion(p)), error = \(e) "MISSING"), character(1))
  # 开发版形态按 x.y.z.9xxx 判（GitHub/universe 构建的惯例），不能简单看 "\.9"——
  # mlr3misc 0.9.12 这种正规 CRAN 版本号里也带 ".9"，那样判会天天假告警。
  dev = core[grepl("^\\d+\\.\\d+\\.\\d+\\.9", core_v)]
  if (length(dev))
    cat(sprintf("::warning::核心包不是 CRAN release 版本（落到了 universe 的开发版？）: %s\n",
      paste(sprintf("%s=%s", dev, core_v[dev]), collapse = ", ")))
  cat(paste(c(
    sprintf("::notice::deps need=%d todo=%d retry=%d still_missing=%s",
      length(need), length(todo), length(still0_hard),
      if (length(still)) paste(still, collapse = ",") else "-"),
    sprintf("::notice::R %s | %s", paste(R.version$major, R.version$minor, sep = "."),
      paste(sprintf("%s=%s", key, vers), collapse = " ")),
    sprintf("::notice::libPaths[1] = %s", .libPaths()[1]),
    sprintf("::notice::repos = %s | soft_anchor %s = %s",
      paste(sprintf("%s=%s", names(repos_all), repos_all), collapse = " "), anchor_soft,
      if (installed(anchor_soft)) as.character(packageVersion(anchor_soft)) else "MISSING(相关键 SKIP)"),
    # 留一行可 grep 的通道纯度账：CRAN 9 = 门禁测的就是 CRAN 那一版
    sprintf("::notice::cran_release core=%d dev=%s", length(core),
      if (length(dev)) paste(dev, collapse = ",") else "-")
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
