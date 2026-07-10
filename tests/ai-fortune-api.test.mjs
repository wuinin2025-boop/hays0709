import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const root = new URL("../", import.meta.url);
const read = (relativePath) => readFileSync(new URL(relativePath, root), "utf8");

assert.equal(existsSync(new URL("server.mjs", root)), true, "AI proxy server should exist");
assert.equal(existsSync(new URL(".env.example", root)), true, "env example should exist");

const server = read("server.mjs");
const html = read("瀚纳仕H5 demo-启动舱.html");
const readme = read("README.md");
const gitignore = read(".gitignore");
const envExample = read(".env.example");
const combined = [server, html, readme, gitignore, envExample].join("\n");

assert.match(server, /\/api\/fortune/, "server should expose a fortune API route");
assert.match(server, /HAYS_AI_API_KEY/, "server should read the private API key from env");
assert.match(server, /DEEPSEEK_API_KEY/, "server should support DeepSeek's env var name");
assert.match(server, /https:\/\/api\.deepseek\.com/, "server should default to DeepSeek's API base URL");
assert.match(server, /deepseek-v4-flash/, "server should use the current fast DeepSeek model by default");
assert.match(server, /HAYS_AI_TIMEOUT_MS/, "server should allow AI request timeout configuration");
assert.match(server, /process\.env\.HOST \|\| "127\.0\.0\.1"/, "server should default to loopback binding");
assert.match(server, /45000/, "server should allow enough time for live AI generation");
assert.match(server, /\/chat\/completions/, "server should call the chat completions endpoint");
assert.match(server, /response_format[\s\S]*json_object/, "server should request structured JSON output");
assert.match(server, /function normalizeReport/, "server should normalize model output before returning it");
assert.match(server, /function buildFortuneMessages/, "server should keep prompt construction isolated");

assert.match(html, /const AI_FORTUNE_ENDPOINT = "\/api\/fortune";/);
assert.match(html, /const AI_FORTUNE_TIMEOUT_MS = 45000;/);
assert.match(html, /function createFallbackReport\(\)/);
assert.match(html, /async function requestAiReport/);
assert.match(html, /function normalizeClientReport/);
assert.match(html, /function renderReport/);
assert.match(html, /let loadingRunId = 0;/);
assert.match(html, /fetch\(AI_FORTUNE_ENDPOINT/);
assert.match(html, /catch[\s\S]*fallback/, "front end should fall back to local content if the API fails");
assert.match(html, /escapeHTML\(item\)/, "AI-generated action chips should be escaped");

assert.match(readme, /node server\.mjs/);
assert.match(readme, /HAYS_AI_API_KEY/);
assert.match(readme, /不要把 API Key 写进 HTML/);
assert.match(gitignore, /^\.env$/m);
assert.match(gitignore, /^\.env\.\*$/m);
assert.match(envExample, /HAYS_AI_API_KEY=replace-with-your-key/);
assert.match(envExample, /HAYS_AI_TIMEOUT_MS=45000/);
assert.match(envExample, /HOST=127\.0\.0\.1/);

assert.doesNotMatch(combined, /sk-[A-Za-z0-9]{20,}/, "repository files must not contain real API keys");
