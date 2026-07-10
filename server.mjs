import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";

const rootDir = fileURLToPath(new URL(".", import.meta.url));
const indexFile = "瀚纳仕H5 demo-启动舱.html";
const port = Number(process.env.PORT || 5173);
const host = process.env.HOST || "127.0.0.1";
const apiBaseUrl = (process.env.HAYS_AI_API_BASE_URL || "https://api.deepseek.com").replace(/\/+$/, "");
const model = process.env.HAYS_AI_MODEL || "deepseek-v4-flash";
const aiRequestTimeoutMs = Number(process.env.HAYS_AI_TIMEOUT_MS || 45000);

const mimeTypes = new Map([
  [".html", "text/html; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".svg", "image/svg+xml"],
  [".mp3", "audio/mpeg"],
  [".ico", "image/x-icon"]
]);

createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", `http://${request.headers.host || "127.0.0.1"}`);
    if (url.pathname === "/api/fortune/status") {
      handleFortuneStatusRequest(request, response);
      return;
    }
    if (url.pathname === "/api/fortune") {
      await handleFortuneRequest(request, response);
      return;
    }
    await serveStatic(url.pathname, response);
  } catch (error) {
    console.error(error?.message || error);
    sendJson(response, 500, { error: "Internal server error" });
  }
}).listen(port, host, () => {
  console.log(`Hays server is running at http://${host}:${port}/`);
});

function getAiApiKey() {
  return process.env.HAYS_AI_API_KEY || process.env.DEEPSEEK_API_KEY || process.env.AI_API_KEY || "";
}

function handleFortuneStatusRequest(request, response) {
  if (request.method === "OPTIONS") {
    response.writeHead(204, corsHeaders());
    response.end();
    return;
  }

  if (request.method !== "GET") {
    sendJson(response, 405, { error: "Method not allowed" });
    return;
  }

  sendJson(response, 200, {
    configured: Boolean(getAiApiKey()),
    provider: "deepseek-compatible",
    model
  });
}

async function handleFortuneRequest(request, response) {
  if (request.method === "OPTIONS") {
    response.writeHead(204, corsHeaders());
    response.end();
    return;
  }

  if (request.method !== "POST") {
    sendJson(response, 405, { error: "Method not allowed" });
    return;
  }

  const apiKey = getAiApiKey();
  if (!apiKey) {
    sendJson(response, 503, {
      error: "AI API key is not configured",
      code: "AI_API_KEY_MISSING"
    });
    return;
  }

  const payload = await readJsonBody(request);
  const fallback = normalizeReport(payload.fallback || {});
  const messages = buildFortuneMessages(payload, fallback);

  try {
    const aiResponse = await fetch(`${apiBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`
      },
      signal: AbortSignal.timeout(aiRequestTimeoutMs),
      body: JSON.stringify({
        model,
        messages,
        temperature: 0.96,
        top_p: 0.92,
        max_tokens: 900,
        stream: false,
        response_format: { type: "json_object" }
      })
    });

    const data = await aiResponse.json().catch(() => ({}));
    if (!aiResponse.ok) {
      console.error(`AI provider returned ${aiResponse.status}`);
      sendJson(response, 502, {
        error: "AI provider request failed",
        code: "AI_PROVIDER_ERROR",
        providerStatus: aiResponse.status
      });
      return;
    }

    const content = data?.choices?.[0]?.message?.content;
    const modelReport = parseModelJsonContent(content);
    sendJson(response, 200, {
      report: normalizeReport(modelReport, fallback),
      provider: "deepseek-compatible",
      model
    });
  } catch (error) {
    console.error(`AI fortune request failed: ${error?.name || "Error"}`);
    sendJson(response, 502, {
      error: "AI provider request failed",
      code: "AI_PROVIDER_ERROR"
    });
  }
}

function buildFortuneMessages(payload, fallback) {
  const answers = payload.answers || {};
  const userFacts = {
    name: clipText(answers.name, 16),
    birth: clipText(answers.birth, 20),
    birthPlace: clipText(answers.birthPlace, 40),
    livePlace: clipText(answers.livePlace, 40),
    period: clipText(answers.period, 12),
    theme: clipText(answers.theme, 20)
  };
  const randomSignal = clipText(payload.clientSeed, 80) || randomUUID();

  return [
    {
      role: "system",
      content: [
        "你是 HAYS 的打工玄学内容策划，负责生成适合 H5 分享的职场娱乐文案。",
        "内容要有网感、轻松、有趣、像朋友开玩笑，但不要低俗、冒犯、PUA 或制造焦虑。",
        "不要承诺真实 offer、涨薪、录用结果；把它写成娱乐测试和行动提醒。",
        "必须只输出一个合法 json 对象，不要 Markdown，不要解释。"
      ].join("\n")
    },
    {
      role: "user",
      content: [
        "请根据下面 json 输入，生成一次全新的 AI 打工命盘。",
        "每次都要变：personaName、insight、drawName、drawOracle、actions、risk 都不能只复述兜底文案。",
        "personaSubline 是页面里接在用户名后面的一句话，不要重复用户名。",
        "标题要短、有记忆点、有分享欲，例如像热梗式工牌名，但不要用生僻字。",
        "actions 输出 3 个 4-8 字按钮文案。",
        "scores 取 1 到 5 的整数，水逆预警高代表提醒更强。",
        "EXAMPLE JSON OUTPUT:",
        JSON.stringify({
          personaName: "会议室闪现体",
          personaSubline: "抽到一张本周工牌，别急着开摆，机会可能在群聊边角料里冒头。",
          insight: "本周先把项目亮点讲顺，别让真实实力卡在一句“还行吧”里。",
          drawName: "贵人读不读",
          drawOracle: "有人会看见你，但你得先把信号发得像正事。",
          actions: ["更新简历", "约杯咖啡", "别先自闭"],
          risk: "少在情绪上头时做决定，截图和复盘比嘴硬更旺你。",
          scores: { career: 4, timing: 3, interview: 4, salary: 2 }
        }),
        "USER INPUT JSON:",
        JSON.stringify(userFacts),
        "LOCAL FALLBACK JSON:",
        JSON.stringify(fallback),
        `RANDOM SIGNAL: ${randomSignal}`
      ].join("\n")
    }
  ];
}

function parseModelJsonContent(content) {
  const text = String(content || "").trim();
  if (!text) {
    throw new Error("Empty AI content");
  }

  try {
    return JSON.parse(text);
  } catch {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(text.slice(start, end + 1));
    }
    throw new Error("AI content is not JSON");
  }
}

function normalizeReport(report = {}, fallback = {}) {
  const base = {
    personaName: "人间搞钱符",
    personaSubline: "抽到一张本周工牌，有点东西。截图发群，看看谁先说准。",
    insight: "机会在靠近，但它需要一个能找到你的入口。",
    drawName: "机会动不动",
    drawOracle: "有风，但还没吹到门口。先把窗户打开。",
    actions: ["机会试探", "更新状态", "让入口可见"],
    risk: "别只转发好运，也要给好运留一个能找到你的入口。",
    scores: { career: 3, timing: 3, interview: 3, salary: 3 }
  };
  const fallbackReport = {
    ...base,
    ...fallback,
    scores: { ...base.scores, ...(fallback.scores || {}) }
  };

  return {
    personaName: normalizeText(report.personaName, fallbackReport.personaName, 12),
    personaSubline: normalizeText(report.personaSubline, fallbackReport.personaSubline, 56),
    insight: normalizeText(report.insight, fallbackReport.insight, 64),
    drawName: normalizeText(report.drawName, fallbackReport.drawName, 12),
    drawOracle: normalizeText(report.drawOracle, fallbackReport.drawOracle, 60),
    actions: normalizeActions(report.actions, fallbackReport.actions),
    risk: normalizeText(report.risk, fallbackReport.risk, 64),
    scores: normalizeScores(report.scores, fallbackReport.scores)
  };
}

function normalizeActions(actions, fallbackActions) {
  const cleanActions = Array.isArray(actions)
    ? actions.map(item => normalizeText(item, "", 12)).filter(Boolean).slice(0, 3)
    : [];
  const fallback = Array.isArray(fallbackActions) ? fallbackActions : [];
  return cleanActions.length === 3 ? cleanActions : fallback.slice(0, 3);
}

function normalizeScores(scores = {}, fallbackScores = {}) {
  return {
    career: clampScore(scores.career, fallbackScores.career),
    timing: clampScore(scores.timing, fallbackScores.timing),
    interview: clampScore(scores.interview, fallbackScores.interview),
    salary: clampScore(scores.salary, fallbackScores.salary)
  };
}

function clampScore(value, fallback = 3) {
  const number = Number.isFinite(Number(value)) ? Math.round(Number(value)) : Number(fallback) || 3;
  return Math.max(1, Math.min(5, number));
}

function normalizeText(value, fallback, maxLength) {
  return clipText(value, maxLength) || clipText(fallback, maxLength);
}

function clipText(value, maxLength = 60) {
  const text = String(value || "").replace(/[\r\n\t]+/g, " ").replace(/\s{2,}/g, " ").trim();
  return [...text].slice(0, maxLength).join("");
}

async function readJsonBody(request) {
  let body = "";
  for await (const chunk of request) {
    body += chunk;
    if (body.length > 65536) {
      throw new Error("Request body is too large");
    }
  }
  return body ? JSON.parse(body) : {};
}

async function serveStatic(pathname, response) {
  const decodedPath = decodeURIComponent(pathname);
  const relativePath = decodedPath === "/" ? indexFile : decodedPath.replace(/^\/+/, "");
  const filePath = resolve(rootDir, relativePath);

  if (!filePath.startsWith(rootDir) || !existsSync(filePath) || statSync(filePath).isDirectory()) {
    sendText(response, 404, "Not found");
    return;
  }

  const type = mimeTypes.get(extname(filePath).toLowerCase()) || "application/octet-stream";
  response.writeHead(200, {
    "Content-Type": type,
    "Cache-Control": type.startsWith("text/html") ? "no-store" : "public, max-age=3600"
  });
  createReadStream(filePath).pipe(response);
}

function corsHeaders(extra = {}) {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    ...extra
  };
}

function sendJson(response, status, payload) {
  response.writeHead(status, corsHeaders({ "Content-Type": "application/json; charset=utf-8" }));
  response.end(JSON.stringify(payload));
}

function sendText(response, status, payload) {
  response.writeHead(status, { "Content-Type": "text/plain; charset=utf-8" });
  response.end(payload);
}
