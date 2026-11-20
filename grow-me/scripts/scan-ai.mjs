#!/usr/bin/env node
/**
 * scan-ai.mjs — 扫描本机 AI 客户端 / 运行时，并判断哪些装了 grow-me
 * 零依赖，输出 JSON。被 console.mjs 复用，也可单独跑：
 *   node scripts/scan-ai.mjs
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, basename } from "node:path";
import { homedir } from "node:os";
import { execFileSync } from "node:child_process";

const HOME = homedir();
const LA = process.env.LOCALAPPDATA || join(HOME, "AppData", "Local");
const ROAM = process.env.APPDATA || join(HOME, "AppData", "Roaming");
const PF = process.env.ProgramFiles || "C:\\Program Files";

const safe = (fn, fb) => {
  try {
    return fn();
  } catch {
    return fb;
  }
};
const listDirs = (p) => safe(() => readdirSync(p, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name), []);
const exists = (p) => safe(() => existsSync(p), false);

/** 各 AI 生态的技能根目录（grow-me 装在哪，它就"拥有"这个技能） */
export const SKILL_ROOTS = {
  agents: join(HOME, ".agents", "skills"),
  cursor: join(HOME, ".cursor", "skills"),
  claude: join(HOME, ".claude", "skills"),
  dsh: join(HOME, ".dsh", "skills"),
};

/** 已知 AI：skillRoots 表示该客户端会从哪些根目录加载技能 */
const KNOWN = [
  { name: "Codex CLI", kind: "cli", cmds: ["codex"], dirs: [join(HOME, ".codex")], procs: ["codex"], skillRoots: ["agents"] },
  { name: "Cursor", kind: "client", exe: [join(LA, "Programs", "cursor", "Cursor.exe"), join(PF, "Cursor", "Cursor.exe")], dirs: [join(HOME, ".cursor")], procs: ["Cursor"], skillRoots: ["agents", "cursor"] },
  { name: "Claude Code", kind: "cli", cmds: ["claude"], dirs: [join(HOME, ".claude"), join(LA, "Programs", "claude")], procs: ["claude"], skillRoots: ["claude"] },
  { name: "DeepSeek Harness (DSH)", kind: "runtime", dirs: [join(HOME, ".dsh"), join(HOME, "DSH1")], procs: ["dsh"], skillRoots: ["agents", "dsh"] },
  { name: "Ollama", kind: "runtime", cmds: ["ollama"], exe: [join(LA, "Programs", "Ollama", "ollama.exe")], dirs: [join(HOME, ".ollama")], procs: ["ollama"], skillRoots: [] },
  { name: "LM Studio", kind: "runtime", dirs: [join(HOME, ".lmstudio"), join(LA, "LM-Studio"), join(LA, "Programs", "LM Studio")], procs: ["LM Studio", "lms"], skillRoots: [] },
  { name: "Coze / 扣子", kind: "client", dirs: [join(HOME, ".coze"), join(ROAM, "Coze")], procs: ["Coze", "coze"], skillRoots: ["agents"] },
  { name: "Windsurf", kind: "client", dirs: [join(HOME, ".windsurf"), join(LA, "Programs", "Windsurf")], procs: ["Windsurf"], skillRoots: ["agents"] },
  { name: "Trae", kind: "client", dirs: [join(HOME, ".trae"), join(LA, "Programs", "Trae")], procs: ["Trae"], skillRoots: ["agents"] },
  { name: "Kimi", kind: "client", dirs: [join(ROAM, "kimi-desktop"), join(LA, "Programs", "Kimi")], procs: ["Kimi", "kimi"], skillRoots: ["agents"] },
  { name: "ChatGPT Desktop", kind: "client", dirs: [join(LA, "Programs", "ChatGPT")], procs: ["ChatGPT"], skillRoots: [] },
  { name: "Cline (VSCode)", kind: "extension", dirs: [join(HOME, ".cline")], procs: [], skillRoots: ["agents"] },
  { name: "Continue (VSCode)", kind: "extension", dirs: [join(HOME, ".continue")], procs: [], skillRoots: ["agents"] },
];

const SKILL_MARKERS = ["grow-me", "grow me", "grow_me"];

function findGrowMeIn(root) {
  if (!exists(root)) return [];
  // Windows 路径大小写不敏感：按真实目录名匹配，避免 grow-me / Grow-ME 被当成两个安装
  return listDirs(root)
    .filter((n) => n.toLowerCase().replace(/_/g, "-") === "grow-me")
    .map((n) => join(root, n));
}

function which(cmd) {
  return safe(() => execFileSync("where", [cmd], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).split(/\r?\n/).filter(Boolean), []);
}

function runningProcs() {
  const out = safe(
    () => execFileSync("tasklist", ["/fo", "csv", "/nh"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 8 * 1024 * 1024 }),
    ""
  );
  return out
    .split(/\r?\n/)
    .map((l) => l.split('","')[0].replace(/^"/, "").replace(/"/g, "").replace(/\.exe$/i, "").toLowerCase())
    .filter(Boolean);
}

export function scanAIs() {
  const procs = new Set(runningProcs());
  const results = [];

  for (const k of KNOWN) {
    const evidence = [];
    const paths = [];
    for (const c of k.cmds || []) {
      const hits = which(c);
      if (hits.length) { evidence.push("PATH: " + c); paths.push(...hits); }
    }
    for (const e of k.exe || []) if (exists(e)) { evidence.push("exe: " + e); paths.push(e); }
    for (const d of k.dirs || []) if (exists(d)) { evidence.push("dir: " + d); paths.push(d); }
    const running = (k.procs || []).filter((p) => procs.has(p.toLowerCase()));
    if (running.length) evidence.push("running: " + running.join(","));
    if (evidence.length === 0) continue;

    // 该 AI 能加载的技能根目录里是否有 grow-me
    const skillPaths = [];
    const matchedRoots = [];
    for (const r of k.skillRoots || []) {
      const root = SKILL_ROOTS[r];
      const hits = findGrowMeIn(root);
      if (hits.length) { skillPaths.push(...hits); matchedRoots.push(r); }
    }
    results.push({
      name: k.name,
      kind: k.kind,
      running: running.length > 0,
      runningProcs: running,
      evidence,
      paths,
      skillsSupport: (k.skillRoots || []).length > 0,
      skillInstalled: skillPaths.length > 0,
      skillScope: matchedRoots.length ? matchedRoots.join("+") : null,
      skillPaths,
    });
  }

  const globalInstalls = Object.entries(SKILL_ROOTS)
    .flatMap(([name, root]) => findGrowMeIn(root).map((p) => ({ root: name, path: p })));

  return {
    scanned_at: new Date().toISOString(),
    host: process.env.COMPUTERNAME || "unknown",
    global_skill_installs: globalInstalls,
    ai: results,
    summary: {
      total: results.length,
      running: results.filter((r) => r.running).length,
      withSkill: results.filter((r) => r.skillInstalled).length,
      skillCapable: results.filter((r) => r.skillsSupport).length,
    },
  };
}

if (process.argv[1] && basename(process.argv[1]) === "scan-ai.mjs") {
  console.log(JSON.stringify(scanAIs(), null, 2));
}
