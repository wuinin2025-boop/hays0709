import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const html = readFileSync(new URL("../瀚纳仕H5 demo-启动舱.html", import.meta.url), "utf8");
const legacy = readFileSync(new URL("../瀚纳仕H5 demo.html", import.meta.url), "utf8");

[
  ["formScreen", "form-ritual-screen"],
  ["questionScreen", "question-ritual-screen"],
  ["loadingScreen", "loading-ritual-screen"],
  ["reportScreen", "report-ritual-screen"],
  ["posterScreen", "poster-ritual-screen"]
].forEach(([id, className]) => {
  assert.match(html, new RegExp(`<section class="screen ritual-screen ${className}" id="${id}">`));
});

assert.match(html, /<div class="global-brand-dock">/);
assert.match(html, /<button class="music-toggle global-music-toggle is-muted" id="musicToggle"/);
assert.match(html, /<div class="ritual-page-shell">/);
assert.match(html, /<div class="ritual-step-orbit" aria-hidden="true">/);
assert.match(html, /<div class="loading-oracle-core" aria-hidden="true">/);
assert.match(html, /<div class="poster-aura" aria-hidden="true">/);
assert.match(html, /<img class="qr-wire" src="assets\/hays-qr\.png" alt="Hays 官网二维码">/);
assert.doesNotMatch(html, /二维码占位/);
["form-bg.png", "question-bg.png", "loading-bg.png", "report-bg.png", "poster-bg.png"].forEach(asset => {
  assert.equal(existsSync(new URL(`../assets/${asset}`, import.meta.url)), true, `${asset} should exist`);
  assert.match(html, new RegExp(`assets/${asset}`));
});
["fate-money.png", "fate-ally.png", "fate-chance.png", "fate-offer.png", "fate-retrograde.png", "fate-switch.png"].forEach(asset => {
  assert.equal(existsSync(new URL(`../assets/${asset}`, import.meta.url)), true, `${asset} should exist`);
  assert.match(html, new RegExp(`assets/${asset}`));
});
const ritualBackgroundBlock = html.match(/\.ritual-screen::before \{([\s\S]*?)\n    \}/)?.[1] || "";
const posterCardBlock = html.match(/\.poster-card \{([\s\S]*?)\n    \}/)?.[1] || "";
assert.doesNotMatch(ritualBackgroundBlock, /assets\/home-bg\.png/);
assert.doesNotMatch(posterCardBlock, /assets\/home-bg\.png/);
assert.match(html, /<span class="fate-visual fate-visual--money" aria-hidden="true">/);
assert.match(html, /<span class="fate-visual fate-visual--ally" aria-hidden="true">/);
assert.match(html, /<span class="fate-visual fate-visual--chance" aria-hidden="true">/);
assert.match(html, /<span class="fate-visual fate-visual--offer" aria-hidden="true">/);
assert.match(html, /<span class="fate-visual fate-visual--retrograde" aria-hidden="true">/);
assert.match(html, /<span class="fate-visual fate-visual--switch" aria-hidden="true">/);
assert.match(html, /<span class="fate-copy">钱来不来<\/span>/);
assert.doesNotMatch(html, /background-image: url\("assets\/fate-card-sprite\.png"\);/);
assert.match(html, /\.fate-visual--money \{ background-image: url\("assets\/fate-money\.png"\); \}/);
assert.match(html, /\.fate-visual--offer \{ background-image: url\("assets\/fate-offer\.png"\); \}/);
const fateVisualBlock = html.match(/\.fate-visual \{([\s\S]*?)\n    \}/)?.[1] || "";
assert.match(fateVisualBlock, /position: absolute;/);
assert.match(fateVisualBlock, /inset: 0;/);
assert.match(fateVisualBlock, /width: 100%;/);
assert.match(fateVisualBlock, /height: 100%;/);
assert.match(fateVisualBlock, /background-size: cover;/);
assert.match(fateVisualBlock, /mix-blend-mode: screen;/);
assert.doesNotMatch(fateVisualBlock, /border:/);
assert.doesNotMatch(fateVisualBlock, /border-radius:\s*20px/);
assert.match(html, /\.fate-card\.is-selected \{\n[\s\S]*?outline: 2px solid rgba\(200, 251, 232, \.9\);/);
assert.match(html, /\.ritual-screen \.date-input \{/);
assert.match(html, /-webkit-appearance: none;/);
assert.match(html, /background-position: calc\(100% - 26px\) 50%, calc\(100% - 18px\) 50%, 0 0;/);
assert.match(html, /\.ritual-screen::before/);
assert.match(html, /\.ritual-screen::after/);
assert.match(html, /\.ritual-screen \.section-card/);
assert.match(html, /\.ritual-screen \.option-btn\.is-selected/);
assert.match(html, /\.report-title-block::before/);
assert.match(html, /\.poster-card::before/);
assert.match(html, /@keyframes ritualBgDrift/);
assert.match(html, /@keyframes ritualSweep/);
assert.match(html, /@keyframes oracleSpin/);
assert.match(html, /@keyframes posterAura/);
assert.match(html, /<div class="share-guide" id="shareGuide" aria-hidden="true">/);
assert.match(html, /<div class="poster-qr-block">/);
assert.match(html, /扫码围观我的打工人格，顺手给自己也起一卦。/);
assert.match(html, /\.share-guide\.is-visible/);
assert.match(html, /@keyframes shareArrowFloat/);
assert.match(html, /function openShareGuide\(\)/);
assert.match(html, /分享好友[\s\S]*openShareGuide\(\);/);
assert.match(html, /data-long-press-save="poster"/);
assert.doesNotMatch(html, /poster-save-tip/);
assert.doesNotMatch(html, /长按点亮保存姿势/);
assert.match(html, /const LONG_PRESS_MS = 650;/);
assert.match(html, /function startPosterPress/);
assert.match(html, /function cancelPosterPress/);
assert.match(html, /\.persona-user-name/);
assert.match(html, /function escapeHTML/);
assert.match(html, /personaSubline\.innerHTML/);
assert.match(html, /\.ritual-screen \.index-row \{/);
assert.match(html, /grid-template-areas:\n        "label stars"\n        "track track";/);
assert.match(html, /\.loading-ritual-screen::before/);
assert.doesNotMatch(legacy, /ritual-screen/);
