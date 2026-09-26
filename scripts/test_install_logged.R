# 验证 list_example_deps.R 新装的"安装自带病因" machinery：
#   1) install_logged() 把子进程输出收进文件，且装进了父会话看得见的库目录
#      （只装进临时库，绝不动本机用户库）
#   1c) 长 repos / 长包名向量：deparse 折行曾把子进程脚本劈成两条碎语句（red 模拟实测），
#       这里把它钉成回归——生成的脚本必须能 parse，子进程必须报出 TARGET_LIB
#   2) read_log / pkg_block（Windows 二进制 + Linux 源码两种风味）/ annotate（含元素内部
#      自带换行必须摊平——2026-09-26 CI 上就是没摊平，把真凶劈掉了）/
#      err_window / closure_missing（含索引取不到时的降级路径）/ why_missing /
#      unloadable_deps（"磁盘上有但 dlopen 不了"，closure_missing 的口径抓不到那种）
# 用法：Rscript scripts/test_install_logged.R scripts/list_example_deps.R
#       （它只抽函数定义来跑，不触发主流程；会真的联网装 1 个小包到**临时库**，绝不动用户库）

a = commandArgs(trailingOnly = TRUE)
script = a[1]
if (is.na(script) || !file.exists(script)) stop("给个脚本路径")
tmp_lib = if (is.na(a[2])) file.path(tempdir(), "tmplib") else a[2]
dir.create(tmp_lib, recursive = TRUE, showWarnings = FALSE)

# 只取脚本里的函数定义与常量，不跑主流程（主流程末尾会 quit(1)）
# 注意：这里要跟着脚本一起改。install_logged 现在依赖 artifact_dir 与 dep1，
# 漏一个就是"object not found"，而那种失败长得像 machinery 坏了。
want = c("install_logged", "read_log", "annotate", "flat", "pkg_block", "around", "err_pat",
  "err_window", "closure_missing", "why_missing", "unloadable_deps", "ldd_missing", "installed", "install_logs", "install_rc",
  "rscript_bin", "artifact_dir", "dep1", "repos_all", "base_repos", "universe_repos", "bundled")
top = parse(script)
lhs = function(x) if (is.call(x) && length(x) > 1L && identical(x[[1]], as.name("=")))
  as.character(x[[2]]) else ""
defs = Filter(function(x) lhs(x) %in% want, top)
got = vapply(defs, lhs, character(1))
cat(sprintf("取到 %d 个定义：%s\n", length(defs), paste(got, collapse = ", ")))
missing = setdiff(want, got)
if (length(missing)) cat(sprintf("!! 脚本里没有：%s\n", paste(missing, collapse = ", ")))
stopifnot(!length(missing))

e = new.env(parent = globalenv())
for (x in defs) eval(x, envir = e)
# eval 之后再覆盖：repos_all 换成 TUNA，免得测试自己先去撞 cloud.r-project.org
assign("repos_all", c(TUNA = "https://mirrors.tuna.tsinghua.edu.cn/CRAN"), envir = e)
assign("install_logs", character(0), envir = e)
assign("install_rc", integer(0), envir = e)
# 主流程里那句 dir.create(artifact_dir) 不是赋值，抽定义抽不到它——不补就是 writeLines 报目录不存在
dir.create(e$artifact_dir, recursive = TRUE, showWarnings = FALSE)
cat(sprintf("产物临时目录 = %s\n", e$artifact_dir))

setwd(tempdir())
# 先让临时库成为**父会话**的 [1]：install_logged 就是把父 .libPaths() 原样写给子进程的，
# 所以这一步同时保证了"装不进用户库"。
.libPaths(c(normalizePath(tmp_lib, winslash = "/"), .libPaths()))
tmp_first = .libPaths()[1]
cat("\n=== 1) install_logged：装 fastmap 进临时库 ===\n")
e$install_logged("fastmap", "probe")
lg = e$read_log()
cat(sprintf("日志 %d 行 | source 段 %d | binary 段 %d\n", length(lg),
  sum(startsWith(lg, "* installing *source* package '")),
  sum(startsWith(lg, "* installing *binary* package '"))))
stopifnot(length(lg) > 0L)
got = "fastmap" %in% list.files(tmp_lib)
cat(sprintf("临时库 = %s | 里面有 fastmap = %s | 内容 = %s\n", tmp_first, got,
  paste(list.files(tmp_lib), collapse = " ")))
stopifnot(got)   # 装不到父会话看得见的地方，整套诊断就是自欺
cat("--- 原始日志（看 source/binary 标记到底长什么样）---\n")
writeLines(paste("  |", lg))

cat("\n=== 1b) 退出码必须读得出来（status 属性只在非零时挂）===\n")
writeLines(c('print("before quit")', 'quit(status = 3)'), "badchild.R")
k = system2(e$rscript_bin, c("--no-save", "--no-restore", shQuote("badchild.R")), stdout = TRUE, stderr = TRUE)
cat(sprintf("quit(3) 子进程：attr(status) = %s | 输出 %d 行\n", format(attr(k, "status")), length(k)))
stopifnot(identical(as.integer(attr(k, "status")), 3L))
stopifnot(identical(e$install_rc[["probe"]], 0L))   # 成功那次记 0，不是 NA

cat("\n=== 1c) 回归：长 repos 向量不许把子进程脚本劈碎 ===\n")
# 病根：deparse(命名长向量) 返回多行字符向量，sprintf 按元素循环 -> 生成两条不完整语句。
# 症状极有迷惑性：rc!=0 + 日志里一句 unexpected symbol，看起来像"仓库坏了/网络坏了"。
long_repos = c(
  RSPM = "https://packagemanager.posit.co/cran/__linux__/noble/latest",
  CRAN = "https://mirrors.tuna.tsinghua.edu.cn/CRAN",
  mlorg = "https://mlr-org.r-universe.dev")
stopifnot(length(deparse(long_repos)) > 1L)        # 先确认这个值真的会让 deparse 折行，否则回归是空的
stopifnot(length(e$dep1(long_repos)) == 1L)        # dep1 必须压成单行
# 先把账本清空：read_log() 会把之前 probe 那次的日志一起端出来，回执计数就成假翻倍
assign("install_logs", character(0), envir = e)
assign("install_rc", integer(0), envir = e)
assign("repos_all", long_repos, envir = e)
bad = e$install_logged("nosuchpkgqq123", "longrepo")
genf = file.path(e$artifact_dir, "install_longrepo.R")
stopifnot(file.exists(genf))
cat("--- 生成的子进程脚本 ---\n")
writeLines(paste("  |", readLines(genf, warn = FALSE)))
stopifnot(!inherits(try(parse(genf), silent = TRUE), "try-error"))
lg2 = e$read_log()
stopifnot(!any(grepl("unexpected symbol", lg2, fixed = TRUE)))
tgt2 = grep("^TARGET_LIB:|^REPOS_USED|^REPOS_REQUESTED", lg2, value = TRUE)
cat(sprintf("子进程回执 %d 条 | rc = %s\n", length(tgt2), bad))
writeLines(paste("  |", tgt2))
stopifnot(length(tgt2) >= 2L)
# 装前/装后各报一次状态，是"日志 1079 行、171 个二进制解包、rc=0、而目标包名字零出现"
# 那种形态唯一的抓法——它说明根本没请求过这个包，而不是请求了没装上。
b4 = grep("^BEFORE_INSTALL:", lg2, value = TRUE)
af = grep("^AFTER_INSTALL:", lg2, value = TRUE)
cat(sprintf("装前 %s | 装后 %s\n", b4, af))
stopifnot(length(b4) == 1L, length(af) == 1L,
  any(grepl("nosuchpkgqq123=MISS", b4, fixed = TRUE)),
  any(grepl("nosuchpkgqq123=MISS", af, fixed = TRUE)))
# 仓库回执必须是"每个子进程一条、三套仓库压在同一行"——paste 按元素循环会把它劈成
# 多行并且把 option 的第 i 个仓库配成 requested 的第 i 个（CI 上就这么被骗过一次）
rq = grep("^REPOS_REQUESTED:", lg2, value = TRUE)
op = grep("^REPOS_USED\\(option\\):", lg2, value = TRUE)
cat(sprintf("REPOS_REQUESTED 行数 = %d | REPOS_USED(option) 行数 = %d\n", length(rq), length(op)))
stopifnot(length(rq) == 1L, length(op) == 1L)
stopifnot(sum(grepl("https://", rq)) == 1L)   # 单行含三个 URL，不是三行
writeLines(paste("  |", rq))
# 全库普查两行必须都在（子进程自己算，父会话看不见它的库状态）
ub = grep("^UNLOADABLE_BEFORE:", lg2, value = TRUE)
ua = grep("^UNLOADABLE_AFTER:", lg2, value = TRUE)
cat(sprintf("普查回执：装前 %s | 装后 %s\n", ub, ua))
stopifnot(length(ub) == 1L, length(ua) == 1L,
  !any(grepl("\n", c(ub, ua), fixed = TRUE)),
  !any(grepl("[()>=,]", c(ub, ua))))   # 残留括号 = 版本约束没剥掉，会把约束当包名
# 装的是不存在的包：允许 rc=0（install.packages 只警告）或非零，但不允许"语法碎"
assign("repos_all", c(TUNA = "https://mirrors.tuna.tsinghua.edu.cn/CRAN"), envir = e)
assign("install_logs", character(0), envir = e)
assign("install_rc", integer(0), envir = e)

cat("\n=== 2) pkg_block：两种日志风味都要捞得到 ===\n")
# 风味 A：本机真实日志（Windows 二进制没有 "* installing" 行，只有 successfully unpacked）
blk = e$pkg_block(lg, "fastmap")
cat(sprintf("真实日志里 fastmap 段 %d 行 | 命中行: %s\n", length(blk),
  paste(blk[grep("fastmap", blk, fixed = TRUE)], collapse = " ; ")))
stopifnot(length(blk) > 0L, any(grepl("fastmap", blk, fixed = TRUE)))
stopifnot(length(e$pkg_block(lg, "不存在的包")) == 0L)
# 风味 B：Linux 源码编译（ubuntu job 上的形态，靠 "* installing *source* package 'x' ..." 认包）
srclog = c(rep("padding", 4L), "* installing *source* package 'igraph' ...",
  "** building", "* DONE (igraph)", "* installing *source* package 'kknn' ...",
  "make: *** [Makevars:12] Error 1", "* ERROR: compilation failed for package 'kknn'")
blkb = e$pkg_block(srclog, "kknn")
cat(sprintf("Linux 风味 kknn 段 %d 行 | 含 DONE 之前的别人的行 = %s\n", length(blkb),
  any(grepl("igraph", blkb, fixed = TRUE))))
stopifnot(length(blkb) > 0L, any(grepl("compilation failed", blkb, fixed = TRUE)))

cat("\n=== 3) err_window + annotate（Linux 源码失败风味）===\n")
fake = c(rep("padding", 5L), "* installing *source* package 'igraph' ...",
  "**  ALREADY-COMPILED", "gcc -I... -c foo.c -o foo.o",
  "foo.c:1:10: fatal error: blurb.h: No such file or directory",
  "make: *** [Makevars:12: foo.o] Error 1",
  "* ERROR: compilation failed for package 'igraph'", "* removing '/tmp/lib/igraph'",
  "installation of package 'igraph' had non-zero exit status")
ew = e$err_window(fake)
cat(sprintf("err_window 命中 %d 行；含编译错原文 = %s\n", length(ew),
  any(grepl("blurb.h", ew, fixed = TRUE))))
stopifnot(length(ew) > 0L, any(grepl("blurb.h", ew, fixed = TRUE)),
  any(grepl("non-zero exit status", ew, fixed = TRUE)))
stopifnot(length(e$err_window(c("* installing *source* package 'ok' ...", "* DONE (ok)"))) == 0L)
one = capture.output(e$annotate("error", "T", fake))
stopifnot(length(one) == 1L, grepl("%0A", one, fixed = TRUE), grepl("^::error::", one))
cat(sprintf("annotate 输出确实是单行工作流命令（%d 行，含 %%0A）\n", length(one)))
# 回归（2026-09-26 CI 真事故）：**元素内部**自带换行时也必须只出一行。
# 老写法只在元素之间 join %0A，元素内的裸换行原样漏出去，::error:: 从中间被劈断，
# 而 dlopen 报错的第二行（真凶 libglpk…cannot open shared object file）恰好在后半句。
dlopen = "unable to load shared object '.../igraph.so':\n  libglpk.so.40: cannot open shared object file: No such file or directory"
two = capture.output(e$annotate("error", "加载失败原文", dlopen))
cat(sprintf("自带换行的单条输入 -> 输出 %d 行\n", length(two)))
stopifnot(length(two) == 1L, !any(grepl("\n", two, fixed = TRUE)),
  startsWith(two, "::error::"),
  grepl("libglpk.so.40", two, fixed = TRUE),      # 真凶没被劈掉
  grepl("%0A", two, fixed = TRUE))

cat("\n=== 4) closure_missing：把『什么都不缺』变成可造的条件 ===\n")
# 本机那份 R 库就是全量用户库（近千个包），收窄 .libPaths() 造不出"缺依赖"的现场
# （第一次就是这么测的：结果永远"无"，等于没测）。所以直接把 installed.packages 换成空库桩。
cm_real = e$closure_missing("kknn")
cat(sprintf("真实库下 kknn 缺的传递依赖 = %s\n", if (length(cm_real)) paste(cm_real, collapse = ", ") else "无"))
assign("installed.packages", function(...) matrix(character(0), nrow = 0L, ncol = 1L,
  dimnames = list(NULL, "Package")), envir = e)
cm = e$closure_missing("kknn")
cat(sprintf("空库桩下 kknn 缺的传递依赖 %d 个 = %s\n", length(cm), paste(cm, collapse = ", ")))
stopifnot(length(cm) > 0L, "igraph" %in% cm, "Matrix" %in% cm, !("stats" %in% cm))
assign("installed.packages", utils::installed.packages, envir = e)

cat("\n=== 5) closure_missing 降级：仓库索引取不到时必须明说，不能装成『什么都不缺』===\n")
# 这条是 2026-09-26 那个 invalid 'filters' argument 的教训：tryCatch 把错误吞成 NULL，
# 结果"传递依赖里还缺: 无"——一个假绿灯，比红难查十倍。
assign("available.packages", function(...) stop("simulated index failure"), envir = e)
cm_bad = NULL
d = capture.output(assign("cm_bad", e$closure_missing("kknn"), envir = e))
cat(sprintf("返回值长度 = %d | 输出: %s\n", length(e$cm_bad), paste(d, collapse = " / ")))
stopifnot(length(e$cm_bad) == 0L, any(grepl("^::warning::", d)))
assign("available.packages", utils::available.packages, envir = e)

cat("\n=== 6) why_missing：把 requireNamespace(quietly=TRUE) 咽掉的原文捞回来 ===\n")
# "缺"至少三种病：压根没装上、装完反而加载不了（遮蔽）、磁盘上有但 dlopen 不了（缺系统库）。
# 后两种在安装日志里一个字都没有，只有当场 load 一次才说得出原因——所以这条必须有原文，
# 而且两个分支都得挂包名（第 7 节依赖这个约定去取名字）。
w = e$why_missing("nosuchpkgqq123")
cat(" 不存在的包 ->", w, "\n")
stopifnot(startsWith(w, "nosuchpkgqq123 加载失败原文："), nchar(w) > 25L)
# 原文本身也必须被 flatten：conditionMessage 可能自带换行（dlopen 就是），
# 它是拼进 sprintf 再喂 annotate 的，不摊平就会重演上面那条 CI 事故。
stopifnot(!grepl("\n", w, fixed = TRUE))
ok = e$why_missing("fastmap")   # 第 1 步刚装进临时库，父会话看得见
cat(" 已装的包   ->", ok, "\n")
# 成功分支同样挂包名：两个分支的"第一个空格前 = 包名"必须一致，否则下游解析会拿整句当名字
stopifnot(grepl("其实正常", ok, fixed = TRUE), startsWith(ok, "fastmap "))

cat("\n=== 7) unloadable_deps：磁盘上有、却 dlopen 不了的那种病 ===\n")
# closure_missing 的口径是"磁盘上没有"，抓不到 ubuntu 这次的形态（igraph 装着，但它的 .so 加载不了，
# 于是 kknn 报错、日志里一行错都没有、重试还被 install.packages 当"已装"直接跳过）。
# 真凶往往不是清单里那个包，而是它某个"装着但坏了"的依赖——所以这里必须往下钻一层。
mk = function(rows) {
  m = matrix("", nrow = length(rows), ncol = 3L,
    dimnames = list(rows, c("Package", "Imports", "Depends")))
  m
}
stub = mk(c("kknn", "Matrix", "igraph", "fastmap"))
stub["kknn", "Imports"] = "graphics, igraph, Matrix, stats, nosuchpkgqq123, methods"
stub["igraph", "Imports"] = "Matrix, fastmap"
assign("installed.packages", function(...) stub, envir = e)
# 桩"能不能加载"这一步；loadNamespace 仍走真的，负责给原文
rn_real = base::requireNamespace
stubbed = c("igraph", "nosuchpkgqq123")
assign("requireNamespace", function(package, ...) !as.character(package) %in% stubbed, envir = e)
ud = e$unloadable_deps("kknn")
cat(sprintf("kknn 的坏依赖 %d 条 = %s\n", length(ud), paste(ud, collapse = " ; ")))
# 1) 每条都必须以包名开头（下游用 sub(" .*","",.) 取名字去问 ldd；这一条是上一版跑出来的真 bug：
#    成功分支不挂名，整句话被当成包名传给了 ldd_missing）
nm = sub(" .*", "", ud)
stopifnot(length(ud) == 2L, setequal(nm, stubbed),
  all(startsWith(ud, paste0(nm, " "))))
# 2) 真装不上的（igraph 在桩里没有、本机也确实加载不了的那种）给原文；
#    requireNamespace 说不行而 loadNamespace 说行的，给"其实正常"——这本身就是"顺序/瞬时"的信号
stopifnot(any(grepl("^nosuchpkgqq123 加载失败原文", ud)),
  any(grepl("^igraph ", ud)),
  all(grepl("加载失败原文|其实正常", ud)))
# 3) 能加载的依赖和随 R 发行的不许混进来
stopifnot(!any(grepl("\\bstats\\b|graphics|methods|Matrix|fastmap", ud)))
# 4) 每一行都必须是单行（喂给 annotate 前就摊平，别指望下游）
stopifnot(!any(grepl("\n", ud, fixed = TRUE)))
# 磁盘上根本没有的包：返回空，而不是编一条"加载失败"的假原文
assign("requireNamespace", rn_real, envir = e)
stopifnot(length(e$unloadable_deps("absentpkgqq123")) == 0L)
assign("installed.packages", utils::installed.packages, envir = e)
cat("真实库下 kknn 的坏依赖 =", paste(e$unloadable_deps("kknn"), collapse = " ; "),
  "（本机为空 = 依赖全部加载正常）\n")

cat("\n=== 8) ldd_missing：本机只能证它不炸，真效果在 unix job 上 ===\n")
# 这台机器是 Windows，走的是"没有 ldd 就返回空"那条分支；unix 分支（把 "not found" 的行捞出来）
# 只能在 CI 上第一次跑到——所以这里断言的是"绝不报错、绝不返回非字符"，而不是它抓到了什么。
# 如实记：这条是 dry_run 的一半（另一半线上见）。
r1 = e$ldd_missing("absentpkgqq123")
r2 = e$ldd_missing("stats")
cat(sprintf("不存在的包 -> %s | 随发行包 -> %s | OS = %s\n", length(r1), length(r2), .Platform$OS.type))
stopifnot(is.character(r1), is.character(r2), length(r1) == 0L)
stopifnot(identical(.Platform$OS.type, "unix") || (length(r1) == 0L && length(r2) == 0L))

cat("\n=== 9) 普查的解析口径：版本约束必须剥干净 ===\n")
# 这段是子进程 unl() 里那两行的**同一份表达式**（第 1c 节只端到端证明它出了一行）。
# 为什么单独测：DESCRIPTION 里写的是 "Matrix (>= 1.2-0), methods"，切完若不剥括号，
# "(>=" 这种字符串会被当成"加载不了的包"，普查就天天假告警。
# 刻意用 chartr + "[, ]+" 而不是正则反斜杠：反斜杠在拼子进程脚本时最容易少一层。
d = matrix(c("A (>= 1.2), B, C (>= 0.1)", "R (>= 4.0), methods, D,E"), nrow = 2L, ncol = 2L,
  dimnames = list(c("pkg1", "pkg2"), c("Imports", "Depends")))
cs = intersect(c("Imports", "Depends"), colnames(d))
raw = as.character(unlist(d[, cs, drop = FALSE], use.names = FALSE))
x = trimws(unlist(strsplit(chartr("(),>=", "     ", raw), "[, ]+"), use.names = FALSE))
x = x[grepl("^[[:alpha:]][[:alnum:].]*$", x)]      # 与子进程同一道字形过滤
bd = c("methods", "R")
nm9 = unique(setdiff(x, c(bd, "")))
cat("剥完剩下 =", paste(sort(nm9), collapse = ", "), "\n")
# 没加这道过滤时实测会漏出 "1.2" / "4.0" / "0.1"（版本号被当成包名）——单独跑 §9 时抓到的
stopifnot(setequal(nm9, c("A", "B", "C", "D", "E")), !any(grepl("[()>=]", nm9)))

cat("\n全部断言通过\n")
