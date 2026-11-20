#!/usr/bin/env node
/**
 * beacon.mjs — "定位仪"：接手的 AI 向 8176 监测台报到，并上报声明/证据
 * 只上报、不控制。零依赖，Node 18+。
 *
 * 用法：
 *   node scripts/beacon.mjs register --agent win-a --model deepseek-flash [--cwd <dir>]
 *   node scripts/beacon.mjs beat     --agent win-a
 *   node scripts/beacon.mjs watch    --agent win-a --every 30     # 保活心跳（前台循环）
 *   node scripts/beacon.mjs claim --agent win-a --claim "P1 完成，loss 8.61" --evidence "runs/p1-s1/train.log:100"
 *   node scripts/beacon.mjs telemetry --agent win-a --tokens 84213 --waste 12040 \
 *        --ctx-used 45120 --ctx-max 64000 --tool-calls 37 --dup-reads 3 --dup-runs 2 --big-outputs 1
 *   node scripts/beacon.mjs status                                # 看监测台里有哪些 agent
 * 全局：--console http://127.0.0.1:8176
 */
import { readFileSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_URL = "http://127.0.0.1:8176";

function parseArgs(argv) {
  const cmd = argv[0] && !argv[0].startsWith("--") ? argv[0] : "";
  const opts = {};
  for (let i = cmd ? 1 : 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--")) continue;
    const k = argv[i].slice(2);
    const v = argv[i + 1];
    if (v === undefined || v.startsWith("--")) opts[k] = true;
    else { opts[k] = v; i++; }
  }
  return { cmd, opts };
}

function consoleUrl(opts) {
  if (opts.console) return String(opts.console);
  try {
    const rt = JSON.parse(readFileSync(join(homedir(), ".grow-me", "console", "runtime.json"), "utf8"));
    if (rt.url) return rt.url;
  } catch {}
  return DEFAULT_URL;
}

/** 找本机安装的 grow-me 及其版本（"持证"依据） */
function detectSkill() {
  const roots = [
    join(homedir(), ".agents", "skills"),
    join(homedir(), ".cursor", "skills"),
    join(homedir(), ".claude", "skills"),
    join(homedir(), ".dsh", "skills"),
  ];
  for (const r of roots) {
    const p = join(r, "grow-me", "SKILL.md");
    if (existsSync(p)) {
      const m = /version:\s*(V?\d+\.\d+\.\d+)/.exec(readFileSync(p, "utf8"));
      return { version: m ? m[1] : "unknown", path: join(r, "grow-me") };
    }
  }
  // 兜底：本脚本所在技能目录
  const fallback = join(HERE, "..", "SKILL.md");
  if (existsSync(fallback)) {
    const m = /version:\s*(V?\d+\.\d+\.\d+)/.exec(readFileSync(fallback, "utf8"));
    return { version: m ? m[1] : "unknown", path: resolve(HERE, "..") };
  }
  return { version: "unknown", path: null };
}

async function post(base, path, body) {
  const res = await fetch(base + path, {
    method: "POST",
    headers: { "content-type": "application/json; charset=utf-8" },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({ ok: false, error: "non-json" }));
  if (!res.ok) throw new Error(JSON.stringify(data));
  return data;
}
async function get(base, path) {
  const res = await fetch(base + path);
  return res.json();
}

function payload(opts, skill) {
  return {
    agent: opts.agent || "unknown",
    model: opts.model || null,
    cwd: opts.cwd ? resolve(String(opts.cwd)) : process.cwd(),
    pid: process.pid,
    skill_version: skill.version,
    skill_path: skill.path,
    // 是否真的在用技能工作（仅声明，监测台据此区分"使用技能"与"仅绑定"）
    skill_used: opts["skill-used"] === "false" ? false : opts["skill-used"] === "true" ? true : null,
    ts: new Date().toISOString(),
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const { cmd, opts } = parseArgs(process.argv.slice(2));
  const base = consoleUrl(opts);
  const skill = detectSkill();

  switch (cmd) {
    case "register":
    case "beat": {
      const out = await post(base, "/api/beacon", payload(opts, skill));
      console.log(JSON.stringify(out, null, 2));
      return;
    }
    case "watch": {
      const every = Math.max(5, Number(opts.every || 30)) * 1000;
      console.log(JSON.stringify({ ok: true, watching: true, agent: opts.agent, console: base, every_sec: every / 1000 }));
      for (;;) {
        try {
          const out = await post(base, "/api/beacon", payload(opts, skill));
          if (out && out.ok === false) console.error(JSON.stringify(out));
        } catch (e) {
          console.error(JSON.stringify({ ok: false, error: String(e.message || e) }));
        }
        await sleep(every);
      }
    }
    case "claim": {
      if (!opts.claim) throw new Error("missing --claim");
      const out = await post(base, "/api/claims", {
        agent: opts.agent || "unknown",
        model: opts.model || null,
        claim: String(opts.claim),
        evidence: opts.evidence ? String(opts.evidence) : "",
        source: "beacon",
      });
      console.log(JSON.stringify(out, null, 2));
      return;
    }
    case "telemetry": {
      const n = (v) => (v === undefined ? 0 : Number(v));
      const out = await post(base, "/api/telemetry", {
        agent: opts.agent || "unknown",
        tokens: n(opts.tokens),
        waste: n(opts.waste),
        ctx_used: n(opts["ctx-used"]),
        ctx_max: n(opts["ctx-max"]),
        tool_calls: n(opts["tool-calls"]),
        dup_reads: n(opts["dup-reads"]),
        dup_runs: n(opts["dup-runs"]),
        big_outputs: n(opts["big-outputs"]),
        note: opts.note || null,
      });
      console.log(JSON.stringify(out, null, 2));
      return;
    }
    case "status": {
      const out = await get(base, "/api/agents");
      console.log(JSON.stringify(out, null, 2));
      return;
    }
    default:
      console.log(JSON.stringify({
        ok: false,
        error: "unknown command",
        commands: ["register", "beat", "watch", "claim", "telemetry", "status"],
        console: base,
        detected_skill: skill,
      }, null, 2));
  }
}

main().catch((e) => {
  console.error(JSON.stringify({ ok: false, error: String(e && e.message ? e.message : e) }));
  process.exit(1);
});
