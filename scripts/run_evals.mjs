#!/usr/bin/env node
// run_evals.mjs —— ml-mlr3 evals 断言评分器（零依赖 Node >= 18）
//
// 配套 evals.json：把每个 eval prompt 发给装好本 skill 的 Agent，
// 回答原样存为 evals/outputs/eval-<id>.md，然后：
//
//   node scripts/run_evals.mjs              # 评分 evals/outputs/ 下全部回答
//   node scripts/run_evals.mjs <file...>    # 评分指定回答文件
//   node scripts/run_evals.mjs --selftest   # 引擎自检（黄金样例应 0 FAIL，违规样例应全命中）
//   node scripts/run_evals.mjs --json ...   # 机器可读输出
//
// 退出码：0 = 全 PASS（WARN 不算失败）；1 = 有 FAIL；2 = 用法/文件错误。
// 断言为静态代码审计（正则启发式），标 heuristic 处可能误报，需人工复核。
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SEED_BLACKLIST = new Set([1, 42, 123, 111, 222, 333, 999, 2024, 2025, 2026]);

// ---- 代码预处理：拆行、剔注释（整行 # 注释 + 行尾 # 注释），返回 [{n, text}] ----
function codeLines(code) {
  return code.split(/\r?\n/).map((text, i) => ({ n: i + 1, text }))
    .map(({ n, text }) => ({ n, text: text.replace(/#.*$/, "") }))
    .filter(({ text }) => text.trim().length > 0);
}
function allCodeLines(blocks) {
  let offset = 0;
  return blocks.flatMap((block) => {
    const lines = codeLines(block).map(({ n, text }) => ({ n: n + offset, text }));
    offset += block.split(/\r?\n/).length;
    return lines;
  });
}

// ---- 断言注册表：fn(ctx) => {status: "PASS"|"FAIL"|"WARN", detail?} ----
// ctx = { text: 回答全文, code: 拼接代码, lines: 有效代码行 }
const REGISTRY = {
  no_common_seed(ctx) {
    const hits = [];
    for (const { n, text } of ctx.lines) {
      const m = [...text.matchAll(/set\.seed\s*\(\s*(\d+)\s*\)/g)];
      for (const s of m) if (SEED_BLACKLIST.has(Number(s[1]))) hits.push(`第 ${n} 行: set.seed(${s[1]})`);
    }
    return hits.length ? { status: "FAIL", detail: hits.join("; ") } : { status: "PASS" };
  },
  no_dev_testset_use(ctx) {
    const hits = ctx.lines.filter(({ text }) => text.includes("split$test"))
      .map(({ n, text }) => `第 ${n} 行: ${text.trim().slice(0, 80)}`);
    return hits.length ? { status: "FAIL", detail: hits.join("; ") } : { status: "PASS" };
  },
  r_coding_style(ctx) {
    const patterns = [
      [/<-/, "<- 赋值"], [/\bfunction\s*\(/, "function() 匿名函数"],
      [/\bifelse\s*\(/, "ifelse()"], [/\bmerge\s*\(/, "merge()"],
      [/%>%/, "magrittr %>%"], [/\bgather\s*\(/, "gather()"],
      [/\bspread\s*\(/, "spread()"], [/\bgroup_by\s*\(/, "group_by() 常驻分组"],
    ];
    const hits = [];
    for (const { n, text } of ctx.lines)
      for (const [re, label] of patterns)
        if (re.test(text)) hits.push(`第 ${n} 行 ${label}`);
    return hits.length ? { status: "FAIL", detail: [...new Set(hits)].join("; ") } : { status: "PASS" };
  },
  pipeop_pipe_syntax(ctx) {
    // heuristic：单行审计。po(/ppl( 等图组件后用 |> 串联 = 违规；%>>% 才是图连接。
    const hits = ctx.lines
      .filter(({ text }) => /\b(po|ppl|pos|gunion)\s*\(/.test(text) && /\|>/.test(text) && !text.includes("%>>%"))
      .map(({ n, text }) => `第 ${n} 行: ${text.trim().slice(0, 80)}`);
    return hits.length ? { status: "FAIL", detail: hits.join("; ") } : { status: "PASS" };
  },
  parallel_authorized(ctx) {
    if (!/future::plan|plan\s*\(/.test(ctx.code)) return { status: "PASS" };
    const asked = /询问|是否需要|是否使用|是否允许|征得|授权|许可|征询|permission/i.test(ctx.text);
    return asked ? { status: "PASS" } : { status: "FAIL", detail: "出现 future::plan 但全文无并行授权询问" };
  },
  refuses_violation(ctx) {
    // heuristic：eval-2 类拦截题，回答须含拒绝/纠正语义
    const ok = /不能|不可以|不建议|不要这样|拒绝|泄露|红线|错误|风险|正确做法|正确写法|data leakage|leakage/i.test(ctx.text);
    return ok ? { status: "PASS" } : { status: "FAIL", detail: "未检出拒绝/纠正语义（heuristic）" };
  },
  time_aware_resampling(ctx) {
    // 时序题：须显式时间切分 + rsmp("custom") 滚动折。
    // 事实：mlr3 ≤1.7.x 内置字典无 rolling_origin；order 角色不改变随机 CV/holdout 切分（实测）。
    const hasCustom = /rsmp\s*\(\s*["']custom["']/.test(ctx.code);
    const hasOrderRole = /set_col_roles\s*\([^)]*["']order["']/.test(ctx.code);
    const explicitSplit = /seq_len\s*\(|floor\s*\(/.test(ctx.code);
    const randomCV = /rsmp\s*\(\s*["']cv["']/.test(ctx.code);
    if (hasCustom && (hasOrderRole || explicitSplit)) return { status: "PASS" };
    const detail = [];
    if (!hasCustom) detail.push("未用 rsmp(\"custom\") 滚动折（rolling_origin 在内置字典不存在）");
    if (!hasOrderRole && !explicitSplit) detail.push("未见显式时间切分或 order 角色");
    if (randomCV && !hasCustom) detail.push("时序场景出现随机 rsmp(\"cv\")");
    return { status: "FAIL", detail: detail.join("; ") };
  },
  smote_in_graph(ctx) {
    const hasSmote = /smote/i.test(ctx.code);
    const hasPo = /po\(\s*["']smote["']/i.test(ctx.code);
    const inGraph = ctx.code.includes("%>>%");
    if (hasPo && inGraph) return { status: "PASS" };
    return hasSmote
      ? { status: "FAIL", detail: "SMOTE 未封装进 %>>% 图链（po(\"smote\") 缺失或不在图中）" }
      : { status: "FAIL", detail: "未检出图内 SMOTE 方案" };
  },
  explains_nested_purpose(ctx) {
    // heuristic：嵌套重抽样用途题
    const unbiased = /无偏|泛化|unbiased|generalization/i.test(ctx.text);
    const tuned = /auto_tuner|\$train\s*\(/.test(ctx.text);
    return unbiased && tuned ? { status: "PASS" } : { status: "FAIL", detail: "未同时说明「无偏/泛化估计」与 auto_tuner$train 调参路径（heuristic）" };
  },
  visualizes_evaluation(ctx) {
    return /autoplot|ggplot|\broc\b|prc|calibrat|残差|residual|混淆|confusion/i.test(ctx.text)
      ? { status: "PASS" }
      : { status: "WARN", detail: "未发现评估可视化线索（heuristic）" };
  },
};

// ---- 引擎 ----
function extractRBlocks(text) {
  return [...text.matchAll(/```r\s*\n([\s\S]*?)```/gi)].map((m) => m[1]);
}
function runAssertions(evaL, text) {
  const blocks = extractRBlocks(text);
  const ctx = { text, code: blocks.join("\n"), lines: allCodeLines(blocks) };
  return (evaL.assertions ?? []).map((a) => {
    const fn = REGISTRY[a.name];
    if (!fn) return { name: a.name, status: "WARN", detail: "未知断言名（注册表未实现）" };
    const r = fn(ctx);
    const severity = (a.severity ?? "FAIL").toUpperCase();
    // 断言声明的 severity 只会降级（FAIL→WARN），不会升 WARN→FAIL
    const status = severity === "WARN" && r.status === "FAIL" ? "WARN" : r.status;
    return { name: a.name, status, detail: r.detail, heuristic: /heuristic|启发/.test(a.check ?? "") };
  });
}

function scoreFile(evalsIndex, file) {
  const text = readFileSync(file, "utf8");
  const id = Number((path.basename(file).match(/eval-(\d+)/) ?? [])[1]);
  const evaL = evalsIndex.evals.find((e) => e.id === id);
  if (!evaL) return { id, file, error: `evals.json 中无 id=${id}` };
  const results = runAssertions(evaL, text);
  return { id, file, title: evaL.title, results };
}

function fmtScore(s) {
  if (s.error) return `== eval-${s.id} ==\n  [ERROR] ${s.error}\n`;
  const lines = s.results.map((r) => {
    const tag = r.status === "PASS" ? "PASS" : r.status;
    const extra = [r.detail, r.heuristic && r.status !== "PASS" ? "(heuristic,需人工复核)" : ""]
      .filter(Boolean).join(" —— ");
    return `  [${tag}] ${r.name}${extra ? " —— " + extra : ""}`;
  });
  const n = (k) => s.results.filter((r) => r.status === k).length;
  return `== eval-${s.id} ${s.title} (${path.basename(s.file)}) ==\n${lines.join("\n")}\n  小计: ${n("PASS")} PASS, ${n("FAIL")} FAIL, ${n("WARN")} WARN\n`;
}

// ---- selftest：黄金样例应 0 FAIL；违规样例应命中 5 个 FAIL ----
function selftest() {
  const goodSample = [
    "```r",
    "library(mlr3verse)",
    "set.seed(7291)",
    "task = as_task_classif(df, target = \"churn\", positive = \"yes\")",
    "split = partition(task, ratio = 0.7)",
    "train_task = task$clone(deep = TRUE)$filter(split$train)",
    "glrn = ppl(\"robustify\") %>>% lrn(\"classif.rpart\", predict_type = \"prob\") |> as_learner()",
    "rr = resample(train_task, glrn, rsmp(\"cv\", folds = 5))",
    "rr$aggregate(msr(\"classif.auc\"))",
    "autoplot(rr, type = \"roc\")",
    "# 模型定型后询问用户：是否允许对保留测试集做一次最终评估？（split$test 此前不得使用）",
    "```",
  ].join("\n");
  const badSample = [
    "```r",
    "set.seed(42)",
    "split = partition(task, ratio = 0.7)",
    "pred = lrn(\"classif.svm\")$train(task)$predict(task, row_ids = split$test)",
    "g = po(\"scale\") |> po(\"pca\")",
    "y <- 5",
    "f = function(x) ifelse(x > 1, 1, 0)",
    "future::plan(\"multisession\", workers = 8)",
    "```",
  ].join("\n");

  const allAsserts = [
    { name: "no_common_seed" }, { name: "no_dev_testset_use" }, { name: "r_coding_style" },
    { name: "pipeop_pipe_syntax" }, { name: "parallel_authorized" }, { name: "visualizes_evaluation", severity: "WARN" },
  ];
  const fake = { assertions: allAsserts };
  const good = runAssertions(fake, goodSample);
  const bad = runAssertions(fake, badSample);

  const goodFails = good.filter((r) => r.status === "FAIL");
  const badFails = bad.filter((r) => r.status === "FAIL").map((r) => r.name);
  const expectedBad = ["no_common_seed", "no_dev_testset_use", "r_coding_style", "pipeop_pipe_syntax", "parallel_authorized"];
  const missing = expectedBad.filter((n) => !badFails.includes(n));

  console.log("[selftest] 黄金样例 FAIL 数 =", goodFails.length, goodFails.length === 0 ? "(OK)" : "(应=0)");
  console.log("[selftest] 违规样例命中 =", badFails.join(", "));
  if (missing.length) console.log("[selftest] 漏检:", missing.join(", "));
  const ok = goodFails.length === 0 && missing.length === 0;
  console.log(ok ? "[selftest] 引擎自检 PASS" : "[selftest] 引擎自检 FAIL");
  return ok ? 0 : 1;
}

// ---- main ----
function main() {
  const args = process.argv.slice(2);
  const asJson = args.includes("--json");
  const rest = args.filter((a) => !a.startsWith("--"));
  if (rest.includes("--selftest") || args.includes("--selftest")) process.exit(selftest());

  let files = rest;
  if (files.length === 0) {
    const outDir = path.join(ROOT, "evals", "outputs");
    if (!existsSync(outDir)) {
      console.error(`未找到 ${outDir}。把回答存为 eval-<id>.md 后重跑，或显式传文件路径。`);
      process.exit(2);
    }
    files = readdirSync(outDir).filter((f) => /^eval-\d+\.(md|txt)$/.test(f)).map((f) => path.join(outDir, f));
  }
  if (files.length === 0) { console.error("evals/outputs/ 下没有 eval-<id>.md 回答文件。"); process.exit(2); }

  const evalsIndex = JSON.parse(readFileSync(path.join(ROOT, "evals.json"), "utf8"));
  const scores = files.map((f) => scoreFile(evalsIndex, f));

  if (asJson) { console.log(JSON.stringify(scores, null, 2)); }
  else console.log(scores.map(fmtScore).join("\n"));

  const flat = scores.flatMap((s) => s.results ?? []);
  const fails = flat.filter((r) => r.status === "FAIL");
  const warns = flat.filter((r) => r.status === "WARN");
  console.log(`== 汇总：${flat.filter((r) => r.status === "PASS").length} PASS, ${fails.length} FAIL, ${warns.length} WARN（共 ${scores.length} 个回答）==`);
  if (!asJson) for (const f of fails) console.log(`FAIL: eval-${f.name}: ${f.detail ?? ""}`);
  process.exit(fails.length > 0 ? 1 : 0);
}

main();
