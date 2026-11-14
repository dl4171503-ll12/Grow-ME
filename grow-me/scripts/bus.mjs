#!/usr/bin/env node
/**
 * grow-me 多 Agent 总线（Webhook + 邮箱 + 回执）
 * 零依赖。默认只绑定 127.0.0.1，数据落在 ~/.grow-me/bus（可用 --root 或 GROW_ME_BUS_DIR 改）。
 *
 * 服务端:
 *   node bus.mjs serve [--port 8787] [--host 127.0.0.1] [--root <dir>]
 * 客户端:
 *   node bus.mjs register --agent a1 [--label 窗口A] [--cwd <dir>]
 *   node bus.mjs send --from a1 --to a2 --body "..." [--topic] [--kind note|request|handoff|reply|nudge]
 *                     [--ref <file>]... [--requires-ack false] [--by <iso>]
 *   node bus.mjs inbox  --agent a2 [--since <iso>] [--unread]
 *   node bus.mjs read   --id <msgId> --by a2
 *   node bus.mjs ack    --id <msgId> --by a2 [--note "读了，结论是…"]
 *   node bus.mjs pending --agent a2 [--minutes 5]
 *   node bus.mjs nudge  --id <msgId> --from a1 [--note "..."]
 *   node bus.mjs agents
 *   node bus.mjs wait   --agent a2 [--timeout 60] [--id <msgId>]
 *   node bus.mjs status
 * 全局参数: --url <http://host:port>（缺省读 runtime.json）
 */
import http from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { createHash, randomUUID } from "node:crypto";

const DEFAULT_PORT = 8787;
const OFFLINE_MS = 5 * 60 * 1000;
const MAX_BODY = 1024 * 1024;

// ---------------- helpers ----------------
function parseArgs(argv) {
  const cmd = argv[0] && !argv[0].startsWith("--") ? argv[0] : "";
  const opts = {};
  const start = cmd ? 1 : 0;
  for (let i = start; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) {
      opts[key] = true;
    } else if (opts[key] !== undefined) {
      opts[key] = [].concat(opts[key], next);
      i++;
    } else {
      opts[key] = next;
      i++;
    }
  }
  return { cmd, opts };
}

const busRoot = (opts = {}) =>
  resolve(opts.root || process.env.GROW_ME_BUS_DIR || join(homedir(), ".grow-me", "bus"));

const paths = (root) => ({
  root,
  registry: join(root, "agents.json"),
  runtime: join(root, "runtime.json"),
  messages: join(root, "messages"),
  logs: join(root, "logs"),
});

const readJson = (file, fallback) => {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch {
    return fallback;
  }
};
const writeJson = (file, data) => {
  mkdirSync(join(file, ".."), { recursive: true });
  writeFileSync(file, JSON.stringify(data, null, 2) + "\n", "utf8");
};

function msgDirs(p) {
  if (!existsSync(p.messages)) return [];
  return readdirSync(p.messages, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => join(p.messages, d.name));
}

function allMessages(p) {
  const out = [];
  for (const dir of msgDirs(p)) {
    for (const f of readdirSync(dir)) {
      if (!f.endsWith(".json")) continue;
      const m = readJson(join(dir, f), null);
      if (m && m.id) out.push(m);
    }
  }
  return out;
}

function findMessage(p, id) {
  for (const dir of msgDirs(p)) {
    const file = join(dir, id + ".json");
    if (existsSync(file)) return { msg: readJson(file, null), file };
  }
  return null;
}

function saveMessage(p, msg) {
  writeJson(join(p.messages, msg.to, msg.id + ".json"), msg);
}

function hashFile(file) {
  try {
    return createHash("sha1").update(readFileSync(file)).digest("hex").slice(0, 12);
  } catch {
    return null;
  }
}

const KINDS = ["note", "request", "handoff", "reply", "nudge"];

function buildMessage(opts, refs) {
  const from = opts.from || opts.agent;
  const to = opts.to;
  const body = typeof opts.body === "string" ? opts.body : "";
  if (!from) return { error: "missing --from" };
  if (!to) return { error: "missing --to" };
  if (!body.trim()) return { error: "missing --body" };
  const kind = (opts.kind && String(opts.kind)) || "note";
  if (!KINDS.includes(kind)) return { error: "invalid kind, expected one of: " + KINDS.join("|") };
  const requiresAck = !(opts["requires-ack"] === "false" || opts["requires-ack"] === false);
  const now = new Date().toISOString();
  const msg = {
    id: "m-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6),
    from,
    to,
    topic: (opts.topic && String(opts.topic)) || "(no topic)",
    kind,
    body: body.trim(),
    refs,
    requires_ack: requiresAck,
    expect_reply_by: opts.by
      ? String(opts.by)
      : requiresAck
        ? new Date(Date.now() + 30 * 60 * 1000).toISOString()
        : null,
    created_at: now,
    state: "unread",
    read_at: null,
    acked_at: null,
    ack_by: null,
    ack_note: null,
  };
  return { msg };
}

function makeRef(file) {
  const abs = resolve(String(file));
  return { path: abs, sha1: hashFile(abs), exists: existsSync(abs) };
}

// ---------------- server ----------------
function startServer(opts) {
  const root = busRoot(opts);
  const p = paths(root);
  mkdirSync(p.messages, { recursive: true });
  mkdirSync(p.logs, { recursive: true });

  const send = (res, code, data) => {
    const payload = JSON.stringify(data);
    res.writeHead(code, { "content-type": "application/json; charset=utf-8" });
    res.end(payload);
  };

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    const route = url.pathname;
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > MAX_BODY) req.destroy();
    });
    req.on("end", () => {
      let body = {};
      if (raw) {
        try {
          body = JSON.parse(raw);
        } catch {
          return send(res, 400, { ok: false, error: "invalid JSON body" });
        }
      }
      try {
        if (route === "/health") return send(res, 200, { ok: true, ts: new Date().toISOString(), root });

        if (route === "/register" && req.method === "POST") {
          const reg = readJson(p.registry, { agents: {} });
          const id = body.agent;
          if (!id) return send(res, 400, { ok: false, error: "missing agent" });
          reg.agents[id] = {
            label: body.label || id,
            cwd: body.cwd || null,
            last_seen: new Date().toISOString(),
          };
          writeJson(p.registry, reg);
          return send(res, 200, { ok: true, agent: id });
        }

        if (route === "/agents") {
          const reg = readJson(p.registry, { agents: {} });
          const now = Date.now();
          const agents = Object.entries(reg.agents).map(([id, a]) => ({
            id,
            ...a,
            online: now - Date.parse(a.last_seen || 0) < OFFLINE_MS,
          }));
          return send(res, 200, { ok: true, agents });
        }

        if (route === "/send" && req.method === "POST") {
          const refs = Array.isArray(body.refs) ? body.refs.map((r) => (typeof r === "string" ? makeRef(r) : r)) : [];
          const { msg, error } = buildMessage(body, refs);
          if (error) return send(res, 400, { ok: false, error });
          saveMessage(p, msg);
          return send(res, 200, { ok: true, id: msg.id, to: msg.to, state: msg.state });
        }

        if (route === "/inbox") {
          const agent = url.searchParams.get("agent");
          const since = url.searchParams.get("since");
          const unread = url.searchParams.get("unread") === "1";
          if (!agent) return send(res, 400, { ok: false, error: "missing agent" });
          let list = allMessages(p).filter((m) => m.to === agent);
          if (since) list = list.filter((m) => m.created_at > since);
          if (unread) list = list.filter((m) => m.state === "unread");
          list.sort((a, b) => (a.created_at < b.created_at ? -1 : 1));
          return send(res, 200, { ok: true, agent, count: list.length, messages: list });
        }

        if ((route === "/read" || route === "/ack") && req.method === "POST") {
          const found = findMessage(p, body.id);
          if (!found) return send(res, 404, { ok: false, error: "message not found" });
          const m = found.msg;
          if (route === "/read") {
            m.state = m.state === "acked" ? "acked" : "read";
            m.read_at = m.read_at || new Date().toISOString();
          } else {
            m.state = "acked";
            m.acked_at = new Date().toISOString();
            m.ack_by = body.by || m.to;
            m.ack_note = body.note || null;
          }
          writeJson(found.file, m);
          return send(res, 200, { ok: true, id: m.id, state: m.state });
        }

        if (route === "/pending") {
          const agent = url.searchParams.get("agent");
          const minutes = Number(url.searchParams.get("minutes") || 5);
          const cutoff = Date.now() - minutes * 60 * 1000;
          if (!agent) return send(res, 400, { ok: false, error: "missing agent" });
          const list = allMessages(p).filter(
            (m) =>
              m.to === agent &&
              m.requires_ack &&
              m.state !== "acked" &&
              Date.parse(m.created_at) < cutoff
          );
          return send(res, 200, { ok: true, agent, count: list.length, messages: list });
        }

        if (route === "/verify") {
          const found = findMessage(p, url.searchParams.get("id"));
          if (!found) return send(res, 404, { ok: false, error: "message not found" });
          const refs = (found.msg.refs || []).map((r) => {
            const exists = r.path ? existsSync(r.path) : false;
            const actual = exists ? hashFile(r.path) : null;
            return {
              path: r.path,
              exists,
              expected: r.sha1 || null,
              actual,
              match: exists && r.sha1 ? actual === r.sha1 : false,
            };
          });
          return send(res, 200, {
            ok: true,
            id: found.msg.id,
            refs,
            has_refs: refs.length > 0,
            // 没有引用的消息不算"漂移"，用 null 区分"无引用"与"校验失败"
            all_match: refs.length === 0 ? null : refs.every((r) => r.match),
          });
        }

        if (route === "/nudge" && req.method === "POST") {
          const found = findMessage(p, body.id);
          if (!found) return send(res, 404, { ok: false, error: "original message not found" });
          const original = found.msg;
          const nudge = {
            id: "m-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6),
            from: body.from || original.from,
            to: original.to,
            topic: "nudge: " + original.topic,
            kind: "nudge",
            body:
              (body.note ? body.note + "\n\n" : "") +
              "【催办】上一封消息还没收到回执：" +
              original.id +
              "（topic: " +
              original.topic +
              "）。请 read + ack，并回一句结论。",
            refs: [],
            requires_ack: true,
            expect_reply_by: null,
            created_at: new Date().toISOString(),
            state: "unread",
            read_at: null,
            acked_at: null,
            ack_by: null,
            ack_note: null,
            nudge_of: original.id,
          };
          saveMessage(p, nudge);
          return send(res, 200, { ok: true, id: nudge.id, nudge_of: original.id });
        }

        return send(res, 404, { ok: false, error: "no route " + route });
      } catch (err) {
        return send(res, 500, { ok: false, error: String(err && err.message ? err.message : err) });
      }
    });
  });

  const host = (opts.host && String(opts.host)) || "127.0.0.1";
  let port = Number(opts.port || DEFAULT_PORT);
  const listen = () =>
    server.listen(port, host, () => {
      const runtime = { url: `http://${host}:${port}`, host, port, root, pid: process.pid, started_at: new Date().toISOString() };
      writeJson(p.runtime, runtime);
      console.log(JSON.stringify({ ok: true, ...runtime }, null, 2));
    });
  server.on("error", (err) => {
    if (err.code === "EADDRINUSE" && port < Number(opts.port || DEFAULT_PORT) + 20) {
      port += 1;
      return listen();
    }
    console.error(JSON.stringify({ ok: false, error: String(err.message || err) }));
    process.exit(1);
  });
  listen();
}

// ---------------- client ----------------
function runtimeUrl(opts) {
  if (opts.url) return String(opts.url);
  if (process.env.GROW_ME_BUS_URL) return process.env.GROW_ME_BUS_URL;
  const p = paths(busRoot(opts));
  const rt = readJson(p.runtime, null);
  return rt && rt.url ? rt.url : `http://127.0.0.1:${DEFAULT_PORT}`;
}

async function call(opts, path, method = "GET", body = null) {
  const url = runtimeUrl(opts) + path;
  let lastErr = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const res = await fetch(url, {
        method,
        headers: body ? { "content-type": "application/json; charset=utf-8" } : undefined,
        body: body ? JSON.stringify(body) : undefined,
      });
      const data = await res.json().catch(() => ({ ok: false, error: "non-json response" }));
      if (!res.ok && data.ok !== false) data.ok = false;
      return data;
    } catch (err) {
      // Windows 上偶发 ECONNREFUSED/ECONNRESET，短退避重试 3 次即可
      lastErr = err;
      await new Promise((r) => setTimeout(r, 250 * (attempt + 1)));
    }
  }
  return {
    ok: false,
    error: "cannot reach bus at " + url + " (" + String((lastErr && lastErr.message) || lastErr) + ")",
    hint: "先运行: node scripts/bus.mjs serve",
  };
}

const out = (data) => console.log(JSON.stringify(data, null, 2));

async function main() {
  const { cmd, opts } = parseArgs(process.argv.slice(2));
  switch (cmd) {
    case "serve":
      return startServer(opts);

    case "register":
      return out(await call(opts, "/register", "POST", { agent: opts.agent, label: opts.label, cwd: opts.cwd || process.cwd() }));

    case "agents":
      return out(await call(opts, "/agents"));

    case "send": {
      const refs = [].concat(opts.ref || []).filter(Boolean).map(makeRef);
      const body = {
        from: opts.from,
        to: opts.to,
        body: opts.body,
        topic: opts.topic,
        kind: opts.kind,
        refs,
        "requires-ack": opts["requires-ack"],
        by: opts.by,
      };
      return out(await call(opts, "/send", "POST", body));
    }

    case "inbox": {
      const q = new URLSearchParams({ agent: opts.agent || "" });
      if (opts.since) q.set("since", String(opts.since));
      if (opts.unread) q.set("unread", "1");
      return out(await call(opts, "/inbox?" + q.toString()));
    }

    case "read":
      return out(await call(opts, "/read", "POST", { id: opts.id, by: opts.by }));

    case "ack":
      return out(await call(opts, "/ack", "POST", { id: opts.id, by: opts.by, note: opts.note }));

    case "pending": {
      const q = new URLSearchParams({ agent: opts.agent || "", minutes: String(opts.minutes || 5) });
      return out(await call(opts, "/pending?" + q.toString()));
    }

    case "verify": {
      const q = new URLSearchParams({ id: String(opts.id || "") });
      return out(await call(opts, "/verify?" + q.toString()));
    }

    case "nudge":
      return out(await call(opts, "/nudge", "POST", { id: opts.id, from: opts.from, note: opts.note }));

    case "status":
      return out(await call(opts, "/health"));

    case "wait": {
      const agent = opts.agent;
      if (!agent) return out({ ok: false, error: "missing --agent" });
      const timeoutMs = Number(opts.timeout || 60) * 1000;
      const start = Date.now();
      const since = new Date().toISOString();
      const targetId = opts.id;
      let last;
      while (Date.now() - start < timeoutMs) {
        if (targetId) {
          const r = await call({ ...opts, url: runtimeUrl(opts) }, "/inbox?" + new URLSearchParams({ agent }).toString());
          const hit = (r.messages || []).find((m) => m.id === targetId);
          if (hit && hit.state === "acked") return out({ ok: true, waited_ms: Date.now() - start, message: hit });
          last = hit;
        } else {
          const r = await call(opts, "/inbox?" + new URLSearchParams({ agent, since }).toString());
          if ((r.count || 0) > 0) return out({ ok: true, waited_ms: Date.now() - start, messages: r.messages });
        }
        await new Promise((r) => setTimeout(r, 1000));
      }
      return out({ ok: false, error: "timeout", waited_ms: Date.now() - start, last: last || null });
    }

    default:
      return out({
        ok: false,
        error: "unknown command",
        commands: ["serve", "register", "agents", "send", "inbox", "read", "ack", "pending", "nudge", "verify", "status", "wait"],
      });
  }
}

main().catch((err) => out({ ok: false, error: String(err && err.message ? err.message : err) }));
