import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const html = readFileSync(new URL("../瀚纳仕H5 demo.html", import.meta.url), "utf8");

assert.match(html, /<section class="screen home-screen is-active" id="homeScreen">/);
assert.match(html, /<img class="hays-logo"/);
assert.match(html, /<button class="music-toggle is-muted"/);
assert.match(html, /aria-pressed="false"/);
assert.match(html, /<audio id="bgMusic"/);
assert.match(html, /<div class="home-bg-layer"/);
assert.match(html, /<div class="home-motion-layer"/);
assert.match(html, /<div class="home-content-layer"/);
assert.match(html, /--home-title-top: 132px;/);
assert.match(html, /--home-action-top: 1108px;/);
assert.match(html, /--home-safe-bottom: 1350px;/);
assert.match(html, /url\("assets\/home-bg\.png"\) center 112px \/ 730px auto no-repeat/);
assert.match(html, /<div class="home-title-stage">/);
assert.match(html, /<h1 aria-label="今天的班，先让 AI 给你起一卦">/);
assert.match(html, /<span data-title="今天的班，先让 AI" aria-hidden="true">今天的班，先让 AI<\/span>/);
assert.match(html, /<span data-title="给你起一卦" aria-hidden="true">给你起一卦<\/span>/);
assert.match(html, /报上打工代号和出生坐标，看看你最近进的是搞钱局、贵人局，还是水逆闪避局。/);
assert.doesNotMatch(html, /<div class="home-eyebrow">AI 打工命盘<\/div>/);
assert.match(html, /<button class="primary-btn home-start-btn" type="button" data-goto="formScreen">先抽一签<\/button>/);
assert.match(html, /<span class="music-note"/);
assert.match(html, /@keyframes portalPulse/);
assert.match(html, /@keyframes musicBars/);
assert.match(html, /function toggleMusic/);
