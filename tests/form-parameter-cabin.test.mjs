import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const html = readFileSync(new URL("../瀚纳仕H5 demo-启动舱.html", import.meta.url), "utf8");

[
  "birthYear",
  "birthMonth",
  "birthDay",
  "birthProvince",
  "birthCity",
  "birthDistrict",
  "liveProvince",
  "liveCity",
  "liveDistrict"
].forEach(id => {
  assert.match(
    html,
    new RegExp(`<select class="date-input native-select-hidden" id="${id}"`),
    `${id} should remain as a hidden native data source`
  );
});

[
  ["birthSelector", "birth"],
  ["birthPlaceSelector", "birthPlace"],
  ["livePlaceSelector", "livePlace"]
].forEach(([id, group]) => {
  assert.match(
    html,
    new RegExp(`id="${id}"[\\s\\S]*?data-picker-group="${group}"`),
    `${id} should open one grouped picker`
  );
});

assert.doesNotMatch(html, /class="select-proxy-arrow"/);
assert.match(html, /\.parameter-selector-arrow\s*\{/);
assert.match(html, /\.parameter-selector-values\s*\{[\s\S]*?grid-template-columns: repeat\(3, minmax\(0, 1fr\)\);/);
assert.doesNotMatch(html, /grid-template-columns: 2fr 1fr 1fr;/);
assert.match(html, /<div class="select-picker-columns" id="selectPickerColumns">/);
assert.match(html, /\.select-picker-column\s*\{/);
assert.match(html, /\.select-picker-column-options\s*\{/);
assert.match(html, /body\.select-picker-open\s*\{/);
assert.match(html, /@media \(min-width: 751px\) \{[\s\S]*?\.select-picker \{/);
assert.doesNotMatch(html, /在同一面板内完成/);
assert.doesNotMatch(html, /select-picker-summary/);
assert.doesNotMatch(html, /selectPickerSummary/);
assert.doesNotMatch(html, /summary: "把年、月、日一次选好"/);
assert.doesNotMatch(html, /summary: "把省、市、区一次选好"/);
assert.match(html, /\.form-ritual-screen #profileForm\s*\{[\s\S]*?margin-top: 30px;[\s\S]*?gap: 24px;/);
assert.match(html, /\.form-ritual-screen #profileForm \.section-card\s*\{[\s\S]*?margin-top: 0;/);

[
  "syncGroupSelector",
  "syncAllGroupSelectors",
  "getPickerColumns",
  "renderGroupedPicker",
  "openGroupedPicker",
  "closeGroupedPicker",
  "confirmGroupedPicker"
].forEach(functionName => {
  assert.match(html, new RegExp(`function ${functionName}\\(`), `${functionName} should exist`);
});

assert.match(html, /selectPickerColumns\.addEventListener\("click"/);
assert.match(html, /data-column-index/);
assert.match(html, /document\.body\.classList\.add\("select-picker-open"\)/);
assert.match(html, /document\.body\.classList\.remove\("select-picker-open"\)/);
assert.match(html, /event\.key === "Escape"/);
assert.match(html, /syncAllGroupSelectors\(\);/);
