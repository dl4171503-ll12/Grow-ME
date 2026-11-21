#!/usr/bin/env node
/**
 * voice-agent.mjs — grow-me 的本地实时语音 Agent 运行时（对齐 LiveKit Agents 的核心能力）
 *
 * 能力对齐（与 livekit/agents 的核心概念一一对应，但零依赖、无需 LiveKit 服务器）：
 *   Agent(instructions, tools) / AgentSession / 轮次检测(turn detection) / 打断(interruption)
 *   / 工具调用(function tools) / 事件钩子(events) / 转写记录(transcript) / 延迟指标(metrics)
 *   / 插件化 STT-LLM-TTS（离线回退 + OpenAI 兼容适配）
 *
 * 用法：
 *   node scripts/voice-agent.mjs demo                        # 内置前台 Agent，命令行对话
 *   node scripts/voice-agent.mjs run --agent <agent.json>    # 自定义 Agent 配置
 *   node scripts/voice-agent.mjs serve --port 8180           # HTTP 服务（含 SSE 事件流）
 *
 * 说明：本文件不实现 WebRTC/SIP/电话；需要生产级通话能力时直接用上游 LiveKit Agents（见
 * references/livekit-agents.md）。
 */
import http from "node:http";
import { readFileSync } from "node:fs";
import { createInterface } from "node:readline";

// ---------------------------------------------------------------------------
// 插件层（与 LiveKit Agents 的 stt/llm/tts 插件对应）
// ---------------------------------------------------------------------------

/** 离线确定性 LLM：按规则回答；配置了 OPENAI_* 时改走 OpenAI 兼容接口 */
function createLLM(opts = {}) {
  const base = opts.baseUrl || process.env.OPENAI_BASE_URL;
  const key = opts.apiKey || process.env.OPENAI_API_KEY;
  const model = opts.model || process.env.OPENAI_MODEL || "gpt-4o-mini";
  const useRemote = Boolean(base && key);

  return {
    name: useRemote ? "openai-compatible:" + model : "offline-rule-llm",
    async chat({ messages, tools }) {
      if (useRemote) {
        const body = {
          model,
          messages,
          ...(tools && tools.length ? { tools: tools.map((t) => ({ type: "function", function: t.schema })) } : {}),
        };
        const res = await fetch(base.replace(/\/$/, "") + "/chat/completions", {
          method: "POST",
          headers: { "content-type": "application/json", authorization: "Bearer " + key },
          body: JSON.stringify(body),
        });
        if (!res.ok) throw new Error("LLM HTTP " + res.status);
        const data = await res.json();
        const msg = data.choices?.[0]?.message ?? {};
        return {
          content: msg.content || "",
          toolCalls: (msg.tool_calls || []).map((c) => ({ name: c.function?.name, args: safeJson(c.function?.arguments) })),
        };
      }
      // 离线规则：先看是否命中工具，再给固定风格回答
      const last = messages[messages.length - 1]?.content || "";
      for (const t of tools || []) {
        if (t.triggers?.some((k) => last.includes(k))) {
          return { content: "", toolCalls: [{ name: t.name, args: { query: last } }] };
        }
      }
      return { content: offlineReply(last, messages), toolCalls: [] };
    },
  };
}

function safeJson(s) {
  try {
    return JSON.parse(s || "{}");
  } catch {
    return {};
  }
}

function offlineReply(text, messages) {
  const t = String(text).trim();
  if (/你好|hello|hi/i.test(t)) return "你好，我是这个工作区的语音助手。有什么要处理的？";
  if (/几点|时间/.test(t)) return "现在是本地时间 " + new Date().toLocaleTimeString("zh-CN");
  if (/帮助|help|能做什么/.test(t)) return "我可以对话、调用工具、记录转写，并支持打断；说“查一下”会触发示例工具。";
  const turns = messages.filter((m) => m.role === "user").length;
  return `收到（第 ${turns} 轮）：“${t.slice(0, 40)}”。这是离线回退回答；配置 OPENAI_API_KEY 后可接真实模型。`;
}

/** 离线 STT：文本模式直接透传；音频模式用能量阈值模拟 VAD */
function createSTT() {
  return {
    name: "offline-stt",
    async transcribe(input) {
      if (typeof input === "string") return { text: input, isFinal: true };
      if (input && input.pcm && input.sampleRate) {
        const rms = rms16(input.pcm);
        return { text: "", isFinal: false, vad: { speaking: rms > (input.threshold ?? 500), rms } };
      }
      return { text: "", isFinal: false };
    },
  };
}

function rms16(buf) {
  const view = new Int16Array(buf.buffer, buf.byteOffset, Math.floor(buf.byteLength / 2));
  let sum = 0;
  for (let i = 0; i < view.length; i++) sum += view[i] * view[i];
  return Math.sqrt(sum / Math.max(1, view.length));
}

/** 离线 TTS：返回文本（真实 TTS 由上游插件提供） */
function createTTS() {
  return {
    name: "offline-tts",
    async synthesize(text) {
      return { text, chunks: splitSentences(text), sampleRate: 24000 };
    },
  };
}

function splitSentences(text) {
  return String(text)
    .split(/(?<=[。！？!?.\n])/)
    .map((s) => s.trim())
    .filter(Boolean);
}

// ---------------------------------------------------------------------------
// AgentSession：生命周期 + 轮次检测 + 打断 + 工具 + 事件（对应 livekit.agents.AgentSession）
// ---------------------------------------------------------------------------
export class AgentSession {
  constructor({ agent, llm, stt, tts, onEvent }) {
    this.agent = agent;
    this.llm = llm || createLLM(agent.llm);
    this.stt = stt || createSTT();
    this.tts = tts || createTTS();
    this.onEvent = onEvent || (() => {});
    this.history = []; // {role, content, at}
    this.events = [];
    this.speaking = false;
    this.generation = 0;
    this.metrics = { turns: 0, interruptions: 0, toolCalls: 0, llmMs: 0, ttsMs: 0 };
    this.startedAt = null;
  }

  emit(type, payload = {}) {
    const ev = { type, at: new Date().toISOString(), ...payload };
    this.events.push(ev);
    try {
      this.onEvent(ev);
    } catch {}
    return ev;
  }

  async start() {
    this.startedAt = new Date().toISOString();
    this.emit("session_started", { agent: this.agent.id || this.agent.name, instructions: this.agent.instructions });
    if (this.agent.greeting) {
      this.history.push({ role: "assistant", content: this.agent.greeting, at: new Date().toISOString() });
      this.emit("agent_reply", { text: this.agent.greeting, greeting: true });
      return this.agent.greeting;
    }
    return null;
  }

  /** 用户一轮输入（文本或 {pcm,sampleRate}）。对应 AgentSession 的用户说话事件 */
  async userTurn(input) {
    const gen = ++this.generation; // 新一轮会作废上一轮未完成的生成
    if (this.speaking) {
      this.metrics.interruptions++;
      this.emit("interrupted", { reason: "barge_in" });
    }
    const stt = await this.stt.transcribe(input);
    if (!stt.isFinal) {
      if (stt.vad) this.emit("vad", stt.vad);
      return { final: false };
    }
    const text = stt.text.trim();
    if (!text) return { final: false };
    this.metrics.turns++;
    this.history.push({ role: "user", content: text, at: new Date().toISOString() });
    this.emit("user_transcript", { text });

    // 轮次检测：一句话里有多个句子就拆开逐句处理（对应 turn detection）
    const sentences = this.agent.turnDetection === "none" ? [text] : splitSentences(text);
    const replies = [];
    for (const sentence of sentences) {
      if (gen !== this.generation) break;
      const r = await this.respond(sentence, gen);
      if (r) replies.push(r);
    }
    return { final: true, reply: replies.join(" "), replies };
  }

  async respond(text, gen = this.generation) {
    this.speaking = true;
    const t0 = Date.now();
    let out;
    try {
      out = await this.llm.chat({
        messages: [
          { role: "system", content: this.agent.instructions || "" },
          ...this.history.map((m) => ({ role: m.role, content: m.content })),
        ],
        tools: (this.agent.tools || []).map((t) => ({ name: t.name, triggers: t.triggers, schema: t.schema })),
      });
    } catch (err) {
      this.speaking = false;
      this.emit("error", { where: "llm", message: String(err.message || err) });
      return "";
    }
    this.metrics.llmMs += Date.now() - t0;
    if (gen !== this.generation) {
      this.speaking = false;
      return "";
    }

    let content = out.content;
    for (const call of out.toolCalls || []) {
      const tool = (this.agent.tools || []).find((t) => t.name === call.name);
      if (!tool) continue;
      this.metrics.toolCalls++;
      this.emit("tool_call", { name: call.name, args: call.args });
      try {
        const result = await tool.handler(call.args || {});
        this.emit("tool_result", { name: call.name, result });
        content = content || (typeof result === "string" ? result : JSON.stringify(result));
      } catch (err) {
        this.emit("error", { where: "tool:" + call.name, message: String(err.message || err) });
      }
    }
    if (!content) content = "（工具已完成，但没有生成回复）";
    const t1 = Date.now();
    const tts = await this.tts.synthesize(content);
    this.metrics.ttsMs += Date.now() - t1;
    this.history.push({ role: "assistant", content, at: new Date().toISOString() });
    this.emit("agent_reply", { text: content, chunks: tts.chunks });
    this.speaking = false;
    return content;
  }

  /** 外部主动打断（对应 AgentSession.interrupt） */
  interrupt(reason = "manual") {
    this.generation++;
    this.metrics.interruptions++;
    this.emit("interrupted", { reason });
  }

  end() {
    this.emit("session_ended", { ...this.metrics });
    return { metrics: this.metrics, events: this.events.length, history: this.history.length };
  }

  transcript() {
    return this.history;
  }
}

// ---------------------------------------------------------------------------
// 内置示例 Agent（对齐 upstream examples/frontdesk 这类前台接待场景）
// ---------------------------------------------------------------------------
export const DEMO_AGENT = {
  id: "grow-me-voice-demo",
  name: "前台接待助手",
  instructions:
    "你是某公司前台语音助手。用简短中文回答；用户问营业时间/位置/预约时调用对应工具；不要编造工具结果。",
  greeting: "你好，这里是前台助手。请问需要什么帮助？",
  turnDetection: "sentence",
  tools: [
    {
      name: "lookup_faq",
      description: "查询营业时间/地址/停车等常见问题",
      triggers: ["营业", "几点", "地址", "停车", "在哪"],
      schema: {
        name: "lookup_faq",
        description: "查询常见问题",
        parameters: { type: "object", properties: { query: { type: "string" } }, required: ["query"] },
      },
      handler: ({ query }) => {
        if (/停车|停车位/.test(query || "")) return "地下 B1 有 50 个访客车位，前 2 小时免费。";
        if (/地址|在哪/.test(query || "")) return "地址：科技园 3 号楼 5 层。";
        return "营业时间：周一至周五 9:00–18:00。";
      },
    },
    {
      name: "book_meeting",
      description: "预约会议室",
      triggers: ["预约", "预订", "订会议室"],
      schema: {
        name: "book_meeting",
        description: "预约会议室",
        parameters: { type: "object", properties: { when: { type: "string" } }, required: ["when"] },
      },
      handler: ({ when }) => "已记录预约：" + (when || "时间待定") + "（示例工具，未真正落库）",
    },
  ],
};

// ---------------------------------------------------------------------------
// 运行模式
// ---------------------------------------------------------------------------
function loadAgent(file) {
  if (!file) return DEMO_AGENT;
  const cfg = JSON.parse(readFileSync(file, "utf8"));
  return {
    ...DEMO_AGENT,
    ...cfg,
    tools: (cfg.tools || DEMO_AGENT.tools).map((t) => ({
      ...t,
      handler: t.handler || ((args) => `工具 ${t.name} 执行成功：${JSON.stringify(args)}`),
    })),
  };
}

async function cmdDemo(opts) {
  const agent = loadAgent(opts.agent);
  const session = new AgentSession({
    agent,
    onEvent: (ev) => {
      if (ev.type === "tool_call") console.log(`  [工具] ${ev.name} ${JSON.stringify(ev.args)}`);
    },
  });
  await session.start();
  console.log("=== " + agent.name + "（输入文字对话，:q 退出，:i 打断）===");
  const tty = process.stdin.isTTY;
  const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: !!tty });
  if (tty) process.stdout.write("你> ");
  for await (const line of rl) {
    const text = String(line).trim();
    if (!text) {
      if (tty) process.stdout.write("你> ");
      continue;
    }
    if (text === ":q") break;
    if (text === ":i") {
      session.interrupt("user_command");
      console.log("（已打断）");
      if (tty) process.stdout.write("你> ");
      continue;
    }
    const r = await session.userTurn(text);
    if (r.final) console.log("助手> " + r.reply);
    if (tty) process.stdout.write("你> ");
  }
  const r = session.end();
  console.log("会话结束", JSON.stringify(r.metrics));
}

async function cmdServe(opts) {
  const port = Number(opts.port || process.env.GROW_ME_VOICE_PORT || 8180);
  const agent = loadAgent(opts.agent);
  const session = new AgentSession({ agent });
  await session.start();
  const sseClients = new Set();
  session.onEvent = (ev) => {
    for (const res of sseClients) {
      try {
        res.write(`data: ${JSON.stringify(ev)}\n\n`);
      } catch {}
    }
  };
  session.emit("server_ready", { port });

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://127.0.0.1");
    const json = (code, obj) => {
      res.writeHead(code, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
      res.end(JSON.stringify(obj));
    };
    if (url.pathname === "/api/health") return json(200, { ok: true, agent: agent.name, llm: session.llm.name, port });
    if (url.pathname === "/api/transcript") return json(200, { ok: true, transcript: session.transcript(), metrics: session.metrics });
    if (url.pathname === "/api/events") {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive" });
      res.write("retry: 3000\n\n");
      sseClients.add(res);
      req.on("close", () => sseClients.delete(res));
      return;
    }
    if (url.pathname === "/api/turn" && req.method === "POST") {
      let raw = "";
      req.on("data", (c) => (raw += c));
      req.on("end", async () => {
        let body = {};
        try {
          body = JSON.parse(raw || "{}");
        } catch {
          return json(400, { ok: false, error: "invalid JSON" });
        }
        const text = (body.text || "").toString();
        if (!text) return json(400, { ok: false, error: "missing text" });
        try {
          const r = await session.userTurn(text);
          return json(200, { ok: true, ...r, metrics: session.metrics });
        } catch (err) {
          return json(500, { ok: false, error: String(err.message || err) });
        }
      });
      return;
    }
    if (url.pathname === "/api/interrupt" && req.method === "POST") {
      session.interrupt("api");
      return json(200, { ok: true });
    }
    if (url.pathname === "/") {
      return json(200, {
        ok: true,
        name: "grow-me voice agent",
        endpoints: ["POST /api/turn {text}", "GET /api/transcript", "GET /api/events", "POST /api/interrupt", "GET /api/health"],
      });
    }
    return json(404, { ok: false, error: "not found" });
  });
  server.listen(port, "127.0.0.1", () => {
    console.log(JSON.stringify({ ok: true, url: `http://127.0.0.1:${port}`, llm: session.llm.name, agent: agent.name }, null, 2));
  });
  process.on("SIGINT", () => {
    session.end();
    server.close(() => process.exit(0));
  });
}

function parseArgs(argv) {
  const cmd = argv[0] && !argv[0].startsWith("--") ? argv[0] : "demo";
  const opts = {};
  for (let i = cmd === argv[0] ? 1 : 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--")) continue;
    const k = argv[i].slice(2);
    const v = argv[i + 1];
    if (v === undefined || v.startsWith("--")) opts[k] = true;
    else {
      opts[k] = v;
      i++;
    }
  }
  return { cmd, opts };
}

const { cmd, opts } = parseArgs(process.argv.slice(2));
if (cmd === "serve") await cmdServe(opts);
else if (cmd === "demo" || cmd === "run") await cmdDemo(opts);
else {
  console.log(JSON.stringify({ ok: false, error: "unknown command", commands: ["demo", "run --agent <json>", "serve --port 8180"] }));
  process.exit(1);
}
