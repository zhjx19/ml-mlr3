// render_evidence_card.mjs —— 把门禁的真实转录渲染成一张 SVG 证据卡（可截图、可 diff）
//
// 为什么是 SVG 而不是 GIF：录制工具（vhs / asciinema / ffmpeg）不是人人都有；
// SVG 只依赖 node，产物是纯文本、可 diff、可提交，任何人 `node scripts/render_evidence_card.mjs`
// 都能从同一份转录重录 —— 满足"Showcase 必须可复现"。
//
// 用法（skill 目录下）：
//   node scripts/render_evidence_card.mjs assets/gates-output-2026-09-26.txt assets/evidence-card.svg

import { readFileSync, writeFileSync } from "node:fs";

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  console.error("用法：node scripts/render_evidence_card.mjs <transcript.txt> <out.svg>");
  process.exit(2);
}

const esc = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const raw = readFileSync(input, "utf8").replace(/\r/g, "").split("\n");
// 只保留有信息量的行：去掉空行与纯 ANNOTATE 噪声，最多 34 行，保证卡片不超高。
const lines = raw
  .filter((l) => l.trim() !== "" && !/^node:fs|^\s+at |Node\.js v|CategoryInfo|FullyQualifiedErrorId/.test(l))
  .slice(0, 34);

const LINE_H = 22;
const PAD = 26;
const TITLE_H = 44;
const W = 1080;
const H = TITLE_H + PAD + lines.length * LINE_H + PAD;

const colorOf = (l) => {
  if (l.startsWith("$ ")) return "#7ee787";           // 命令：绿
  if (l.includes("[PASS]")) return "#7ee787";          // 通过：绿
  if (l.includes("[FAIL]") || l.includes("[幻觉]")) return "#ff7b72"; // 失败：红
  if (l.includes("=== 汇总") || l.includes("[OK]")) return "#79c0ff"; // 汇总：蓝
  if (l.includes("--- 耗时")) return "#a5a5a5";
  return "#c9d1d9";
};

const body = lines
  .map((l, i) => {
    const y = TITLE_H + PAD + (i + 1) * LINE_H - 6;
    return `  <text x="${PAD}" y="${y}" fill="${colorOf(l)}">${esc(l)}</text>`;
  })
  .join("\n");

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="15">
  <rect width="${W}" height="${H}" rx="12" fill="#0d1117"/>
  <rect width="${W}" height="${TITLE_H}" rx="12" fill="#161b22"/>
  <rect y="${TITLE_H - 12}" width="${W}" height="12" fill="#161b22"/>
  <circle cx="28" cy="22" r="7" fill="#ff5f56"/>
  <circle cx="52" cy="22" r="7" fill="#ffbd2e"/>
  <circle cx="76" cy="22" r="7" fill="#27c93f"/>
  <text x="${W / 2}" y="27" fill="#8b949e" text-anchor="middle" font-size="13">ml-mlr3 · gates (real run)</text>
${body}
</svg>
`;

writeFileSync(output, svg);
console.log(`wrote ${output}  (${lines.length} 行, ${W}x${H})`);
