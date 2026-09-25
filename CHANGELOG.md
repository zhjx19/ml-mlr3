# Changelog

本仓库遵循「发版讲清为什么改」的迭代纪律：每个版本记录动机，不只是改动清单。

## [2.3.0] — 2026-09-26 · 把"证据"变成仓库里的可见产物

### Added
- **`examples/EXAMPLE.md` + `examples/replay/`（四份真实对照答案）**。为什么改：上一轮的活体尺量出两个问题——README 只有分数没有产物，新用户 30 秒内看不到"装了它写的代码长什么样"；而仓库里最值钱的对照实验（baseline vs skilled）躺在项目临时目录，别人既看不到也重跑不了。现在两份 baseline、两份 skilled 原文入库，README 首屏一段"30 秒看证据"直接给数字（典型答案 6 项纪律违规 + 8 个幻觉键；按 skill 写的 9/9 PASS + 0 幻觉键），并附两条可粘贴的重跑命令。
- **`scripts/check_answer_api.R`（幻觉键体检）**。为什么改：断言引擎量的是**纪律**，它看不见另一种更致命的失败——代码写得像模像样、断言也全 PASS，但 `po("imputehci")` / `rsmp("cs")` / `tsk("classif", formula=)` / `msr("classif.kappa")` 这些键在 mlr3verse 字典里压根不存在，用户一跑就报错。脚本把回答里 `lrn()/po()/msr()/rsmp()/tnr()/tsk()/ppl()` 的首参逐个用 `$has()` 定性（不用 `$get()`，避免 `po("learner")` 这类"键存在但构造器有必填参数"被误判），不存在时再 `$get()` 一次把字典自己的 "Did you mean" 提示捞出来；参数支持 glob（windows CI 的 pwsh 不展开通配符）。实测：`baseline-*` 16 个唯一键里 8 个幻觉，`skilled-*` 19 个键 0 幻觉；`SKILL.md` + 全部 `references/` + A 组 6 份共 169 个键 0 幻觉。
- **CI 第三道门禁**：`gates.yml` 在骨架回归之后跑一次全库幻觉键体检（`SKILL.md` + `references/**` + `evals/outputs/eval-*.md` + `examples/replay/skilled-*.md`，允许 0 个幻觉键）。为什么加：skill 教的键名靠上游改名而腐烂是真实风险（本轮已见过 `ppl("greplicate")` 迁移），只靠人记得去探测等于没有防线；现在哪天上游改名，门禁先红，而不是等用户投诉"示例跑不通"。README 加 `169 keys, 0 hallucinated` 徽章。

### 已知空白（记下来，下一轮开刀）
- 幻觉键体检只查**键**，不查**参数名与类型**。baseline 里 `po("missind", affects = "numerics")`、`po("scale", which = "numerics")`、`lrn("classif.ranger", respect.ui = TRUE)` 三个参数名全是编的（实测可用：`affect_columns`；`scale` 的参数只有 `center/scale/robust/affect_columns`，`which` 反而是 `missind` 的参数；`respect.unordered.factors`），探针一声不响。把它钉进 `examples/EXAMPLE.md` 的"边界"一节，避免读者以为过了探针就能照抄。
- 双向下放目前只有 2 个 prompt × 2 条件的原文入库（其余 4 个 prompt 的 A/B 只留下断言分数）。

## [2.2.1] — 2026-09-26 · 过尺第二轮：把门禁接到线上 + 正文缺陷逐条现场复核

### Added
- **`.github/workflows/gates.yml`（CI 两道门禁）**。为什么改：这一轮"活体尺"量出的最大事故不是文档写错，而是**线上根本没在活**——本地已经推进到 10 个提交，`origin/main` 仍停在 12 天前的 v2.1.0，而 v2.1 的 SKILL.md 里那整段 `learner$encapsulate = c(...)` 是运行即报错的写法；换句话说本轮所有价值对真实用户是 0，且**没有任何一盏灯会报警**，因为没有 CI。现在：ubuntu + windows 双平台**全量**跑骨架回归（不砍案例、不砍折数、不砍预算），依赖树安装区分硬依赖（`e1071` / `ranger` / `xgboost` / `bestNormalize`，装不上直接红）与可选依赖（`ps` / `mlr3tuningspaces`，缺失由脚本记 SKIP 并在汇总行点名），失败时打印 `sessionInfo()`；另一个 job 跑 `node scripts/run_evals.mjs --selftest`。README 首屏加状态徽章。
- **回归用例 19：「文档口径·spatialsign 归属 / 依赖包 / validate='test' 静默」**。为什么改：这一轮修正的三条正文说法都必须有可重跑的钉子——`po("spatialsign")` 属 mlr3pipelines 且默认作用于全部列（含负值列，行 L2 范数 = 1）、`classif.xgboost` 要的是 `xgboost` 本体而非 `mlr3xgboost`、`set_validate(..., validate = "test")` **不报错**（所以它是静默泄露，只能靠纪律拦，拦不住靠异常）。

### Changed
- **README 明确「CI ≠ 免跑凭证」**。为什么改：CI 一上线最容易被误读成"绿了就不用本地跑"。写清 CI 只证明"这两个平台、这个时点的 CRAN 快照"跑得通，改完示例仍须本机实跑并把通过率写进 CHANGELOG——两个环境的实测记录不能互相顶替。

### Fixed
- **`advanced-workflows.md` 两处 `at$predict(task, row_ids = split$test)` 缺红线 1 护栏**（§3 不平衡调优、§4 联合调优）。为什么改：`evaluation.md` §8 的同款代码前面写着"先停下询问用户，获得许可后"，而这两处只有一行"最终模型在原始测试集上预测"，直接照抄就等于教人开发期碰测试集。现各补一句行内护栏注释，与 SKILL.md 红线 1 的"获授权后的最终评估"口径对齐。
- **`validate = "test"` 的措辞从"仅限资源极度受限时的探索性分析"改为"不用"**。为什么改：原文承认泄露却留了个许可口子，等于给红线 1 开了扇侧门；实测更说明它危险——5 折 CV 下把 `classif.auc` 从 0.7504 抬到 0.7924，`$errors` 表 0 行、`$aggregate()` 返回正常有限值，全程没有任何警告。给出替代口径（调小验证比例或走嵌套重抽样）而不是"少用"。
- **SKILL.md 依赖包提示漏 `classif.xgboost`**。为什么改：`advanced-workflows.md` §3 与 `tuning.md` 的示例都用了它，而提示里只列了 glmnet / ranger / kknn / svm，缺 `xgboost` 时报错信息容易被误当成"要装 mlr3xgboost"。现场探测记录事实：`lrn("classif.xgboost")$packages` = `mlr3, mlr3learners, xgboost`——学习器由 mlr3verse 附带的 mlr3learners 提供，后备包是 `xgboost` 本身；顺带把 `tnr("mbo")`→`mlr3mbo`（mlr3verse 已附带）写进同一行，并给出通用探测式 `$packages`。
- **"数据花费"这一误译全部改为"数据划分 / 测试集动用"**（README 首屏一句、`data-spending.md` 标题、`evals/outputs/eval-1.md` 注释）。为什么改：英文 data spending 指的是"测试集被动用了几次"，直译成"数据花费"在中文里读不出这层意思，而它恰好出现在最该读得懂的两处（首屏一句话定位、参考文件标题）。

### 证伪（现场探测后不改）
- 上一份过尺报告把 `references/feature-engineering/numeric.md` 的 `po("spatialsign")` 标成"归属写错（挂在 mlr3verse 名下）"。实测**证伪**：`PipeOpSpatialSign` 就在 `mlr3pipelines` 命名空间里，只 `library(mlr3pipelines)` 即可从字典取到（`mlr3spatial` 只负责空间任务/后端，不提供它），默认 `affect_columns = selector_all()`，混合符号列同样被行规范化、变换后行 L2 范数 = 1。原文正确，不改；把这条事实钉进用例 19，防下次"看起来像扩展包"的直觉再翻。

### 验证
- `Rscript scripts/verify_examples.R` → **19/19 PASS**（exit 0，无 SKIP），2026-09-26 于 R 4.6.1 / mlr3 1.8.0 / mlr3pipelines 0.12.0 / mlr3tuning 1.7.0 / mlr3fselect 1.7.0 / mlr3mbo 1.2.1 / mlr3tuningspaces 0.7.0 / paradox 1.0.1
- `node scripts/run_evals.mjs --selftest` → 引擎自检 PASS（黄金 0 FAIL、违规 5/5、未闭合 fence 5/5）
- `node scripts/run_evals.mjs` → A 组 6 个回答 26 PASS / 0 FAIL / 0 WARN；B 组阴性对照 12 FAIL 全部抓获
- 线上对账：`main` 已推至含 CI 的提交，`v2.2.0` 标签已发布；`api.github.com` 取回的 v2.2.0 `SKILL.md`（487 行）确认含 `ps_system_memory` 新口径，旧报错写法只出现在"不要这样写"列

## [2.2] — 2026-09-26 · 以 TMwR→mlr3 全量复现为证据源回灌 + 现场探测取代版本对照表

### Changed
- **按「AI 自己也能做对就不写」瘦身本轮新增**（用户 2026-09-26 新纪律）。为什么改：SKILL.md 是常驻 Agent 上下文的载荷，每多一行都在稀释真正拦得住错的约束；把可当场探测的清单当知识存进去，跟上一轮抄 NEWS 版本账目是同一个病。具体砍掉：`rr$iters` 对照行、`$score()` / `$encapsulate()` 形参枚举、`rr$errors` / `learner$log` 列名枚举、`datefeatures` 的 20 个开关名单（改为给探测命令 `mlr_pipeops$get("datefeatures")$param_set$ids()`）、`mlr3verse` 的 11 个 selector 名单（改为 `grep("^selector", getNamespaceExports("mlr3verse"))`，本轮实测 n=11）、bootstrap 的 train/OOB 行数流水账、红线 5 里"粒度"与"内部线程"两条并列压成一条。保留判据：不写会不会做错（会）→ 留；能不能现探（能）→ 只留探测方法。SKILL.md 488 → 479 行。
- **版本锚定改为「现场探测纪律 + 一行实测记录」**。为什么改：上一轮把上游包 NEWS 的增删条目连同版本号抄进了 SKILL.md，形成一张需要持续维护、且会随环境腐烂的版本对照表——用户明确指出这类版本号信息不必进技能。现在规则只有一条：照抄任何对象名/参数名前先当场探测（`mlr_pipeops$keys()`、`$param_set$ids()`、`getNamespaceExports()`、`names(formals(...))`）。全文只保留一行实测记录（日期 + 环境 + 通过率），它回答"这些示例最近何时、在什么环境跑通"，跑通回归后刷新。
- **红线 5 从"并行必须授权"改为"并行自动启用 + 必须先量可用资源"**（用户 2026-09-26 改口）。为什么改：项目里那套"全程单线程、并行要先请示"的约束来自他当时在同一台机器上同时忙很多事，是**临时会话条件**而非长期政策；而"授权"这个动作本身拦不住真实风险——风险是**凭空假设机器空闲**：本机 `future::availableCores()` 恒报 20，同期 `ps::ps_system_memory()` 报内存已用 73%，只盯核心数就会开满 worker 把机器压死。现在正文给探测口径（`availableCores()` 定额度、`ps_system_memory()` 看负载、`percent` 高就下调、跑完 `plan("sequential")` 复原），并写下两个不能用处的实测证据：`future` 没有 `availableMemory()`（只导出 `availableCores`/`availableWorkers`），`memory.limit()` 已不再支持（实测告警且只返回 `Inf`）。断言同步改名 `parallel_authorized` → `parallel_resource_checked`：判据从"出现 `future::plan` 但全文无授权询问"改成"出现 `future::plan` 但全文未探测资源"；A 组黄金样例（`evals/outputs/eval-1.md` 与 selftest 黄金串）改为真写一段"探测 → `set_threads(n = 1L)` → `plan()`"的示范，让这条断言在 PASS 方向上也被实际跑过一次，而不是代码里没出现 `plan()` 就白拿 PASS。
- **`set_threads()` / 折粒度纪律保留在红线 5**。为什么保留：并行粒度是重抽样迭代（折），外层一开并行，learner 内部线程必须压成 1，否则 N 个 worker 各开满核互相争抢——这条与授权政策无关，是并行的正确用法。同时保留一个静默反向陷阱：`set_threads(learner, nthreads = 1)` 的错名被 `...` 吞掉，`n` 落到默认值 `availableCores()`，线程反而被设成满核（实测 20）。
- **`resampling.md` 新增 §10（bootstrap / 报错取消 / 分层口径 / 逐折表）**，§1 选择矩阵加"想要 bootstrap"一行。为什么改：这几条都是复现中真实付出过代价的事实，且今天在现网全部可复现——bootstrap 分析集携带重复行号，绝大多数 PipeOp 在 `$train()` 里断言失败（同一 task 换普通 learner 无恙）；`resample()` 一折出错即取消全部迭代、不返回部分结果；分层不是 `rsmp()` 的参数而是 `stratum` 列角色（实测各折正类占比 sd 0.1095 → 0.0075）；`$score()`（逐折）与 `$aggregate()`（标量均值）是两个口径，`$score()` 形参里没有 `aggregate` 开关。

### Fixed
- **「错误处理与日志」整段写法在现网运行即报错**。为什么改：原文 `learner$encapsulate = c(train = , predict = )` 撞 `cannot change value of locked binding for 'encapsulate'`（`encapsulate` 是方法名），`learner$fallback = ...`、`learner$encapsulation = ...`、`lrn(..., fallback = )` 一律报 `Field/Binding is read-only`。改为 `learner$encapsulate("evaluate", default_fallback(learner))`，并记下 `fallback` 形参无默认值（不传即在调用当下断言失败）、`when` 只接受函数或 `NULL`。此前 14 例回归抓不到它，因为回归里没有任何用例碰过封装 API——现已钉成断言。
- **`po("splines", df = 5)` 直接进图**：默认作用全部列，遇 factor 崩在内部 `quantile()`；改为必须带 `affect_columns`，并写下 `type` 只接受 `polynomial/natural`、`knots` 必须是 list。
- **`classif.svm` 调优示例缺 `type`/`kernel`**：`cost`/`gamma` 是条件参数，不显式设就在 `auto_tuner$train()` 第一步断言失败；三处示例（SKILL.md、tuning.md §1.1/§4、feature-engineering.md §6）全部补齐。
- **`lts()` 语义写错**：原文当作返回搜索空间用，实际返回 `TuningSpace` R6（`$learner` 是 id 字符串），要拿 learner 得 `$get_learner()`；且预置空间仍不替你满足 SVM 的条件参数前置。
- **`mlr_pipeops$keys()` 被写成裸 `po()`/`ppl()`**：裸调用报 `cannot coerce type 'environment' to vector`，改为字典探测的正确写法。

### Added
- **Selector 一节重写**：selector 是 `function(Task) -> character`；`mlr3verse` 只再导出 11 个 `selector_*`，6 个符号类需 `mlr3pipelines::` 前缀，`neg()` 不存在；`selector_type("numeric")` 不含 `integer`；`$state$affected_cols` 不等于真正被变换的列。
- **PipeOp 类型前置表**（splines/boxcox/subsample/select 各自的崩溃条件与报错原文）、`ranger`/`xgboost` 拒绝因子特征的实测报错、日期时间列处理（`po("datefeatures")` 的参数与 `<原列名>.<特征名>` 命名、Date/POSIXct 已可直接插补、`po("materialize")` 无参数、`task$…$materialize_view()`）、`mlr3tuningspaces` 预置空间用法、早停/内部验证分数（`set_validate()` + `msr("best_valid_score"/"internal_valid_score", select = , minimize = )`）、`learner$deadline`。
- **回归用例 14 → 18 例**，并加 SKIP 语义（可选依赖缺失记为 SKIP 而非伪装 PASS）。为什么改：本轮所有新增/修正事实都必须有可重跑的钉子的——每个新断言都对应上面一条正文说法。

### Removed
- 淘汰/不存在的写法从正文中清掉：独立函数 `greplicate()`（改 `ppl("greplicate", graph = , n = )`）、`tsk("pima")`、`fs("forward")`/`fs("backward")`/`fs("bonu")`、`task$correlation()`、`task$cols()`/`$nrow()`/`$row_ids()` 函数式访问、learner 构造参数 `validate =`，以及「新版已移除/新版需用」这类依赖版本对照表的措辞（改为绝对陈述）。

### 未采纳（证据不足）
- 复现笔记里「重复 CV 的标准误收缩比实测 0.57、高于理论下界 1/√5」一条：本轮在两种 SE 定义（naive 全折 `sd/√25`、按 repeat 分块 `sd(均值)/√5`）下都复现不出该方向（实测 0.0240 与 0.0185，比值 1.299 且都低于 0.447），加之 `$score()` 不提供 repeat 列、分块口径只能自己假定迭代号连续。**宁可不写**，留作下轮带 mlr3 官方 SE 估计器再核。

### 验证
- `Rscript scripts/verify_examples.R` → 18/18 PASS（exit 0，无 SKIP），2026-09-26 于 R 4.6.1 / mlr3 1.8.0 / mlr3pipelines 0.12.0 / mlr3tuning 1.7.0 / mlr3fselect 1.7.0 / paradox 1.0.1
- `node scripts/run_evals.mjs --selftest` → 引擎自检 PASS（黄金 0 FAIL、违规 5/5、未闭合 fence 5/5）
- `node scripts/run_evals.mjs` → 26 PASS / 0 FAIL / 0 WARN（6 个回答）
- `node scripts/run_evals.mjs evals/outputs/negative/*.md` → 12 FAIL 全部抓获，含改名后的 `parallel_resource_checked`（违规样本 `workers = 16` 且全文无资源探测）
- 资源探测的两条新说法（`availableMemory` 不存在 / `memory.limit()` 已弃用返回 `Inf` / `ps_system_memory()` 字段）钉进用例 18，本轮实测通过

### Meta
- `.claude-plugin/plugin.json` 2.1.0 与 `marketplace.json` 2.1.1 此前各说各话，统一为 2.2.0。为什么改：两个通道版本号不一致，安装方无法判断自己拿到的是哪一版。

## [2.1.1] — 2026-09-14 · 协议切换为 Apache-2.0

### Changed
- **LICENSE：MIT → Apache-2.0**。为什么改：与同门技能（auto-geogebra 等）统一许可证；Apache-2.0 含明确的专利授权条款，对下游采用者更友好。变更范围：LICENSE 全文替换、README 徽章与 License 节、SKILL.md 补充 `license` 字段、marketplace 版本 2.1.1。

## [2.1] — 2026-09-13 · evals 真实回放 + 时序事实修正

### Fixed
- **时序重抽样事实修正（本轮最重要）**：为什么改——用户提供的上游 changelog 触发 API 复查，实测发现 `rsmp("rolling_origin")` 在 mlr3 1.7.1 内置字典**不存在**（只有 bootstrap/custom/custom_cv/cv/holdout/insample/loo/repeated_cv/subsampling），且 `order` 角色实测**不会**让随机 CV/holdout 按时间切分（holdout 测试集散布中段）。SKILL.md、resampling.md、data-spending.md 原来教的 rolling_origin 写法运行即报错。改为教：按时间位置显式切分 + `rsmp("custom")` 手写滚动折（实测每折训练窗严格早于验证窗）；`group` 角色自动分组切分实测成立，保留。
- **verify_examples.R 增至 6 案例**：为什么改——rolling_origin 之错能静默存活至今，正是因为 verify 没覆盖时序；新增「时序·custom 滚动折」案例（含每折 train<test 断言）防同类回归。重跑 6/6 PASS。
- **评分器未闭合 fence 漏检**：为什么改——B 组阴性对照暴露代码块缺闭合 ``` 时整块不被审计（seed 42 / split$test 全漏）。已修并固化进 selftest（未闭合样例期望 5/5 命中）。
- **parallel_authorized 断言补挂**：为什么改——红线 5（并行需授权）此前没有挂到任何 eval，属于断言覆盖缺口；已挂 eval-1/eval-5。

### Added
- **版本演进提示（上游 changelog 摘要）**入 SKILL.md 版本锚定节：mlr3 1.8.0 BREAKING（pima→diabetes）+ msr("best_valid_score")、mlr3tuning ≥1.6.1 AutoTuner 深克隆修复、mlr3fselect ≥1.7.0 rfecv 方向 bug 修复（低版本 rfecv+最小化指标结果无效）、mlr3pipelines 0.11 实测可用项（插补支持 Date/POSIXct、po("splines")、$predict_newdata_fast）。
- **evals 双向回放闭环**：A 组（按 skill 纪律作答×6）26 断言全 PASS；B 组阴性对照（模拟无 skill 典型错误×6）12 FAIL 全部抓获。回答样例入库 `evals/outputs/` 与 `evals/outputs/negative/`，任何人可重放。

### 验证
- `Rscript scripts/verify_examples.R` → 6/6 PASS（2026-09-13，含时序案例）
- `node scripts/run_evals.mjs --selftest` → 引擎自检 PASS（黄金/违规/未闭合三样例）
- A 组回放 26 PASS / 0 FAIL；B 组阴性对照 12 FAIL 全抓获

### Pub（公开发布改造，发布至 github.com/zhjx19/ml-mlr3）
- 为什么改：私用转公开，按出生证清单补必备件。新增 LICENSE（MIT）、`.claude-plugin/` marketplace 双通道（结构对齐 tidymodels/skills）、README 致谢节与 License 节、安装三通道（skills.sh / plugin marketplace / 手动链接，移除私人路径）；SKILL.md 负触发中本机技能名引用改为通用表述；「与 Autos 版关系」内部历史节归档至本 CHANGELOG 1.x 条目。
- 发布动作：`master` → `main` 改名后首推，tag `v2.1.0`（对应本节 + [2.0] 内容）。

## [2.0] — 2026-09-13 · 鲁班工坊第二轮打磨

### Added
- **SKILL.md「版本锚定」节**：为什么改——mlr3 生态迭代快（本轮实测 mlr3 1.7.1 / R 4.6.1，`verify_examples.R` 5/5 PASS），无版本锚定时 Agent 遇 API 报错无从判断是代码错还是版本差。
- **`evals.json` 2.0 + `scripts/run_evals.mjs`**：为什么改——旧 `test-prompts.json` 只有 3 个 dry-run 提示语、无机器可查标准，评测全凭手感。对齐 tidymodels 官方 skills 的 evals 形态（prompt + expected_output + assertions），扩到 6 题覆盖标准流程/红线拦截/时间序列/不平衡/回归/嵌套重抽样陷阱；评分器零依赖 Node 可跑，自带 `--selftest` 引擎自检（黄金样例 0 FAIL、违规样例 5 断言全命中）。原 `test-prompts.json` 删除（内容被 evals.json 完全覆盖，git 历史可查）。
- **SKILL.md「评估必附可视化」小节**：为什么改——对标 tidymodels 官方 skill 的评估要求（分类 ROC/校准、回归 obs-vs-pred/残差），此前只藏在 `references/evaluation.md` 里，主线不提 Agent 就常漏交付。

### Fixed
- **precrec 依赖活体暴露**：为什么改——`autoplot(type="roc")` 在本机实跑报错 `packages could not be loaded: precrec`（mlr3viz 画 ROC/PRC 依赖它但 mlr3verse 不自带），已装包复测 PASS 并把 precrec 写进「依赖包提示」与可视化代码块注释。
- **frontmatter 负面触发路由**（上轮遗留改动，本轮固化）：description 增加「不要用于」清单，与 tidy-data / data-cleaning / tidymodels skill 划清边界，防止误路由。

### 验证
- `Rscript scripts/verify_examples.R` → 5/5 PASS（2026-09-13）
- `node scripts/run_evals.mjs --selftest` → 引擎自检 PASS

## [1.x] — 2026-08 及之前

- 初始转换（Autos aardio 版 → Claude Code skill）
- Phase 0.5 基线 + auto-optimize 第一轮：frontmatter 对齐、dim2/红线1 references 一致性声明、dim5 依赖包提示与缩写来源、verify 脚本铁律化（见 git log 36c1312 及之前）
