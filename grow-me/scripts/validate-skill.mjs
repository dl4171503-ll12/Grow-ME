import { readFileSync, existsSync, readdirSync } from "node:fs";
import { resolve, dirname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const skillDir = resolve(process.argv[2] ?? join(here, ".."));
const skillFile = join(skillDir, "SKILL.md");
const errors = [];
const warns = [];

if (!existsSync(skillFile)) {
  console.log("FAIL: missing " + skillFile);
  process.exit(1);
}

const text = readFileSync(skillFile, "utf8")
  .replace(/^\uFEFF/, "")
  .replace(/\r\n/g, "\n");
if (text.slice(0, 4) !== "---\n") errors.push("frontmatter must start with ---");
const closeIdx = text.indexOf("\n---", 4);
if (closeIdx < 0) errors.push("frontmatter must close with ---");
const fmText = closeIdx < 0 ? "" : text.slice(4, closeIdx);
const body = closeIdx < 0 ? text : text.slice(closeIdx + 4);

// ---- frontmatter: dependency-free line scanner ----
const fields = {};
const lines = fmText.split("\n");
let idx = 0;
while (idx < lines.length) {
  const line = lines[idx];
  const colon = line.indexOf(":");
  const topLevel = colon > 0 && !line.startsWith(" ") && !line.startsWith("\t");
  if (topLevel) {
    const key = line.slice(0, colon).trim();
    let val = line.slice(colon + 1).trim();
    if (val === ">-" || val === ">" || val === "|" || val === "|-") {
      const parts = [];
      idx += 1;
      while (idx < lines.length && (lines[idx].startsWith(" ") || lines[idx].startsWith("\t"))) {
        parts.push(lines[idx].trim());
        idx += 1;
      }
      fields[key] = parts.join(" ");
      continue;
    }
    fields[key] = val;
  }
  idx += 1;
}

const name = fields.name || "";
const description = fields.description || "";
const versionMatch = fmText.match(/version:\s*(V?\d+\.\d+\.\d+)/);
const version = versionMatch ? versionMatch[1] : "";

if (!name) errors.push("missing frontmatter.name");
if (name.length > 64) errors.push("name longer than 64 chars");
if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name)) errors.push("name must be kebab-case");
if (name !== basename(skillDir)) errors.push("directory name must equal skill name");
if (!description) errors.push("missing frontmatter.description");
const descLen = Array.from(description).length;
if (descLen > 1024) errors.push("description longer than 1024 chars, got " + descLen);
if (!version) errors.push("missing metadata.version (expected Vx.y.z)");
if (!fields.license) warns.push("no license field");
if (text.includes("\t")) warns.push("frontmatter contains tab characters");

// ---- body size & required sections ----
const bodyLines = body.split("\n").length;
if (bodyLines > 500) errors.push("SKILL.md body exceeds 500 lines, got " + bodyLines);
else if (bodyLines > 300) warns.push("body is " + bodyLines + " lines; keep the always-loaded part lean");

const requiredSections = ["\u751f\u6548\u8303\u56f4", "\u81ea\u52a8\u843d\u76d8", "\u4e0a\u4e0b\u6587\u7eaa\u5f8b", "\u8ffd\u95ee", "\u4e94\u7ef4", "\u6536\u5c3e", "\u81ea\u52a8\u6d4b\u8bd5\u8f6e\u6b21", "\u65b0\u6d88\u606f", "\u603b\u7ebf", "\u7ea2\u7ebf", "\u81ea\u68c0"];
for (const sec of requiredSections) {
  if (!body.includes(sec)) errors.push("missing required section keyword: " + sec);
}
const requiredTemplateFields = ["\u8fdb\u5ea6\u56fe", "\u8bc1\u636e", "\u4e0b\u4e00\u6b65", "\u8bb0\u5f55"];
for (const f of requiredTemplateFields) {
  if (!body.includes(f)) errors.push("closing template missing field: " + f);
}
if (!body.includes(".grow-me/")) errors.push("body must reference the .grow-me/ work-record dir");
if (!body.includes("rounds/")) errors.push("body must reference the .grow-me/rounds/ round-log dir");

// 正文里点名的 scripts/*.mjs 必须真实存在
const scriptMentions = [...body.matchAll(/scripts\/[A-Za-z0-9_.-]+\.mjs/g)].map((m) => m[0]);
for (const rel of [...new Set(scriptMentions)]) {
  if (!existsSync(join(skillDir, rel))) errors.push("script mentioned in SKILL.md is missing: " + rel);
}

// ---- relative links ----
const targets = [];
const scanBody = body.replace(/```[\s\S]*?```/g, ""); // 代码块里的示例链接不算引用
for (const piece of scanBody.split("](").slice(1)) {
  const close = piece.indexOf(")");
  if (close >= 0) targets.push(piece.slice(0, close));
}
for (const t of targets) {
  if (/^(https?:|mailto:|#)/.test(t)) continue;
  if (t.startsWith("/") || t.includes("<") || t.includes(">")) continue; // 绝对路径/占位符
  if (t.includes("\\")) {
    errors.push("windows backslash path in link: " + t);
    continue;
  }
  const rel = t.split("#")[0];
  if (!existsSync(join(skillDir, rel))) errors.push("broken link: " + t);
}

// ---- orphan reference files ----
const refDir = join(skillDir, "references");
if (existsSync(refDir)) {
  for (const f of readdirSync(refDir)) {
    if (!f.endsWith(".md")) continue;
    if (!targets.some((t) => t.endsWith("references/" + f))) warns.push("reference not linked from SKILL.md: " + f);
  }
}

// ---- report ----
console.log("skill dir : " + skillDir);
console.log("name      : " + name + "  version: " + (version || "(none)"));
console.log("body lines: " + bodyLines + " / 500");
console.log("links     : " + targets.length + " checked");
for (const w of warns) console.log("warn      : " + w);
for (const e of errors) console.log("error     : " + e);
if (errors.length) {
  console.log("RESULT: FAIL (" + errors.length + " errors)");
  process.exit(1);
}
console.log("RESULT: PASS" + (warns.length ? " (" + warns.length + " warnings)" : ""));
