#!/usr/bin/env node
/**
 * console.mjs — grow-me 8176 监测台（只读监测，不控制任何 AI）
 * 默认 127.0.0.1:8176；端口被占用自动 +1 找空闲端口。
 *
 * 用法:
 *   node scripts/console.mjs [--port 8176] [--host 127.0.0.1] [--root <stateDir>]
 *                            [--runs <checkpointDir>] [--loss <lossCsv>]
 * 接口:
 *   GET  /                    监测台页面
 *   GET  /api/status          总览（端口/扫描/定位仪/证据/loss/备份）
 *   GET  /api/ai              重新扫描本机 AI 与技能安装
 *   GET  /api/agents          定位仪列表（在线/离线、技能版本、证据通过率）
 *   POST /api/beacon          定位仪报到/心跳
 *   GET  /api/claims          证据台账    POST /api/claims {claim,evidence,agent,model}
 *   GET  /api/loss            loss 曲线   POST /api/loss/config {line,targetLow,targetHigh}
 *   GET  /api/checkpoints     模型备份清单
 */
import http from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, statSync, appendFileSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { scanAIs } from "./scan-ai.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_PORT = 8176;
const ONLINE_MS = 90 * 1000;

const safe = (fn, fb) => { try { return fn(); } catch { return fb; } };
const readJson = (f, fb) => { const t = safe(() => readFileSync(f, "utf8"), null); if (!t) return fb; return safe(() => JSON.parse(t), fb); };
const writeJson = (f, d) => { mkdirSync(dirname(f), { recursive: true }); writeFileSync(f, JSON.stringify(d, null, 2) + "\n", "utf8"); };

function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--")) continue;
    const k = argv[i].slice(2);
    const v = argv[i + 1];
    if (v === undefined || v.startsWith("--")) opts[k] = true;
    else { opts[k] = v; i++; }
  }
  return opts;
}
const opts = parseArgs(process.argv.slice(2));
const stateRoot = resolve(opts.root || process.env.GROW_ME_CONSOLE_DIR || join(homedir(), ".grow-me", "console"));
const runsDir = resolve(opts.runs || process.env.GROW_ME_RUNS || "runs");
const lossFile = resolve(opts.loss || process.env.GROW_ME_LOSS || join(".grow-me", "loss", "loss.csv"));
const configFile = join(stateRoot, "config.json");
const claimsFile = join(stateRoot, "claims.jsonl");
const agentsFile = join(stateRoot, "agents.json");
const runtimeFile = join(stateRoot, "runtime.json");

/** 本机安装的技能版本（"持证"基准） */
function installedVersion() {
  const p = safe(() => join(HERE, "..", "SKILL.md"), null);
  if (!p || !existsSync(p)) return "unknown";
  const m = /version:\s*(V?\d+\.\d+\.\d+)/.exec(safe(() => readFileSync(p, "utf8"), ""));
  return m ? m[1] : "unknown";
}
const EXPECTED_VERSION = installedVersion();

const DEFAULT_CONFIG = { line: 8.76, targetLow: 2, targetHigh: 3, note: "line = 瞎猜线 8.76；target = 目标区间 2~3" };
const getConfig = () => ({ ...DEFAULT_CONFIG, ...readJson(configFile, {}) });
const readClaims = () => safe(() => readFileSync(claimsFile, "utf8"), "").split(/\r?\n/).filter(Boolean).map((l) => safe(() => JSON.parse(l), null)).filter(Boolean);
const addClaim = (c) => { mkdirSync(stateRoot, { recursive: true }); appendFileSync(claimsFile, JSON.stringify(c) + "\n", "utf8"); };
const claimsSummary = (claims) => {
  const verified = claims.filter((c) => (c.evidence || "").trim().length > 0 && c.status !== "unverified");
  return { total: claims.length, verified: verified.length, unverified: claims.length - verified.length, lyingRisk: claims.length - verified.length };
};

function readAgents() { return readJson(agentsFile, { agents: {} }); }
function beacons() {
  const now = Date.now();
  const reg = readAgents();
  const claims = readClaims();
  const list = Object.entries(reg.agents || {}).map(([id, a]) => {
    const mine = claims.filter((c) => (c.agent || "console") === id);
    const s = claimsSummary(mine);
    const online = now - Date.parse(a.last_seen || 0) < ONLINE_MS;
    const versionMatch = a.skill_version && a.skill_version === EXPECTED_VERSION;
    return {
      agent: id,
      model: a.model || null,
      cwd: a.cwd || null,
      pid: a.pid || null,
      skill_version: a.skill_version || null,
      skill_path: a.skill_path || null,
      version_match: versionMatch,
      licensed: !!(a.skill_version && a.skill_version !== "unknown"),
      online,
      beats: a.beats || 0,
      first_seen: a.first_seen || null,
      last_seen: a.last_seen || null,
      claims: s,
    };
  });
  list.sort((a, b) => (a.online === b.online ? String(a.agent).localeCompare(String(b.agent)) : a.online ? -1 : 1));
  return { expected_version: EXPECTED_VERSION, online_ms: ONLINE_MS, agents: list, summary: { total: list.length, online: list.filter((a) => a.online).length, licensed: list.filter((a) => a.licensed).length, versionMismatch: list.filter((a) => a.licensed && !a.version_match).length } };
}

function parseLoss() {
  if (!existsSync(lossFile)) return { file: lossFile, exists: false, points: [], stats: null, config: getConfig() };
  const text = safe(() => readFileSync(lossFile, "utf8"), "");
  const points = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || /^[a-z#]/i.test(line)) continue;
    const parts = line.split(/[,;\s]+/).filter(Boolean).map(Number);
    if (parts.length < 2 || Number.isNaN(parts[0]) || Number.isNaN(parts[1])) continue;
    points.push({ step: parts[0], loss: parts[1], phase: parts[2] || null, sub: parts[3] || null });
  }
  const cfg = getConfig();
  const losses = points.map((p) => p.loss);
  const last = losses.length ? losses[losses.length - 1] : null;
  return {
    file: lossFile, exists: true, config: cfg, points,
    stats: {
      count: points.length, first: losses[0] ?? null, last, min: losses.length ? Math.min(...losses) : null,
      max: losses.length ? Math.max(...losses) : null,
      belowLine: last !== null && last < cfg.line,
      inTarget: last !== null && last >= cfg.targetLow && last <= cfg.targetHigh,
    },
  };
}

function listCheckpoints() {
  if (!existsSync(runsDir)) return { dir: runsDir, exists: false, items: [] };
  const items = [];
  for (const ent of safe(() => readdirSync(runsDir, { withFileTypes: true }), [])) {
    if (!ent.isDirectory()) continue;
    const p = join(runsDir, ent.name);
    const st = safe(() => statSync(p), null);
    let size = 0, files = 0;
    const stack = [p];
    while (stack.length) {
      const d = stack.pop();
      for (const f of safe(() => readdirSync(d, { withFileTypes: true }), [])) {
        const fp = join(d, f.name);
        if (f.isDirectory()) stack.push(fp);
        else { files++; size += safe(() => statSync(fp).size, 0); }
      }
    }
    items.push({ name: ent.name, mtime: st ? st.mtime.toISOString() : null, files, sizeMB: Math.round((size / 1048576) * 10) / 10 });
  }
  items.sort((a, b) => String(a.name).localeCompare(String(b.name)));
  return { dir: runsDir, exists: true, items };
}

let startedAt = new Date().toISOString();
let actualPort = Number(opts.port || DEFAULT_PORT);
const host = String(opts.host || "127.0.0.1");

function status() {
  const ai = scanAIs();
  const claims = readClaims();
  return {
    ok: true, now: new Date().toISOString(), started_at: startedAt,
    port: actualPort, host, root: stateRoot, cwd: process.cwd(),
    expected_version: EXPECTED_VERSION,
    ai, beacons: beacons(),
    claims: { items: claims.slice(-80), summary: claimsSummary(claims) },
    loss: parseLoss(), checkpoints: listCheckpoints(),
  };
}

const send = (res, code, data, type = "application/json; charset=utf-8") => {
  const body = typeof data === "string" ? data : JSON.stringify(data);
  res.writeHead(code, { "content-type": type, "cache-control": "no-store" });
  res.end(body);
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  const route = url.pathname;
  let raw = "";
  req.on("data", (c) => { raw += c; if (raw.length > 2 * 1024 * 1024) req.destroy(); });
  req.on("end", () => {
    let body = {};
    if (raw) { try { body = JSON.parse(raw); } catch { return send(res, 400, { ok: false, error: "invalid JSON" }); } }
    try {
      if (route === "/" || route === "/index.html") {
        const html = safe(() => readFileSync(join(HERE, "console.html"), "utf8"), "<h1>console.html missing</h1>");
        return send(res, 200, html, "text/html; charset=utf-8");
      }
      if (route === "/api/status") return send(res, 200, status());
      if (route === "/api/ai") return send(res, 200, { ok: true, ...scanAIs() });
      if (route === "/api/agents") return send(res, 200, { ok: true, ...beacons() });
      if (route === "/api/beacon" && req.method === "POST") {
        if (!body.agent) return send(res, 400, { ok: false, error: "missing agent" });
        const reg = readAgents();
        const prev = reg.agents[body.agent] || { beats: 0, first_seen: new Date().toISOString() };
        reg.agents[body.agent] = {
          model: body.model || prev.model || null,
          cwd: body.cwd || prev.cwd || null,
          pid: body.pid || null,
          skill_version: body.skill_version || prev.skill_version || null,
          skill_path: body.skill_path || prev.skill_path || null,
          first_seen: prev.first_seen,
          last_seen: new Date().toISOString(),
          beats: (prev.beats || 0) + 1,
        };
        writeJson(agentsFile, reg);
        const licensed = !!reg.agents[body.agent].skill_version && reg.agents[body.agent].skill_version !== "unknown";
        const matching = reg.agents[body.agent].skill_version === EXPECTED_VERSION;
        return send(res, 200, { ok: true, agent: body.agent, beats: reg.agents[body.agent].beats, licensed, version_match: matching, expected_version: EXPECTED_VERSION });
      }
      if (route === "/api/claims" && req.method === "GET") {
        const claims = readClaims();
        return send(res, 200, { ok: true, items: claims, summary: claimsSummary(claims) });
      }
      if (route === "/api/claims" && req.method === "POST") {
        if (!body.claim) return send(res, 400, { ok: false, error: "missing claim" });
        const c = {
          id: "c-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 5),
          claim: String(body.claim),
          evidence: body.evidence ? String(body.evidence) : "",
          status: body.evidence ? "verified" : "unverified",
          agent: body.agent ? String(body.agent) : "console",
          model: body.model ? String(body.model) : null,
          source: body.source ? String(body.source) : "console",
          created_at: new Date().toISOString(),
        };
        addClaim(c);
        return send(res, 200, { ok: true, claim: c });
      }
      if (route === "/api/loss") return send(res, 200, { ok: true, ...parseLoss() });
      if (route === "/api/loss/config" && req.method === "POST") {
        const cfg = getConfig();
        if (body.line !== undefined) cfg.line = Number(body.line);
        if (body.targetLow !== undefined) cfg.targetLow = Number(body.targetLow);
        if (body.targetHigh !== undefined) cfg.targetHigh = Number(body.targetHigh);
        writeJson(configFile, cfg);
        return send(res, 200, { ok: true, config: cfg });
      }
      if (route === "/api/checkpoints") return send(res, 200, { ok: true, ...listCheckpoints() });
      return send(res, 404, { ok: false, error: "no route " + route });
    } catch (err) {
      return send(res, 500, { ok: false, error: String(err && err.message ? err.message : err) });
    }
  });
});

function listen(tries) {
  server.listen(actualPort, host, () => {
    writeJson(runtimeFile, { url: `http://${host}:${actualPort}`, host, port: actualPort, pid: process.pid, root: stateRoot, runs: runsDir, loss: lossFile, started_at: startedAt, mode: "monitor-only", skill_version: EXPECTED_VERSION });
    console.log(JSON.stringify({ ok: true, mode: "monitor-only", url: `http://${host}:${actualPort}`, port: actualPort, skill_version: EXPECTED_VERSION, root: stateRoot, runs: runsDir, loss: lossFile }, null, 2));
  });
  server.once("error", (err) => {
    if (err.code === "EADDRINUSE" && tries < 20) { actualPort += 1; setTimeout(() => listen(tries + 1), 30); return; }
    console.error(JSON.stringify({ ok: false, error: err.message }));
    process.exit(1);
  });
}
listen(0);
