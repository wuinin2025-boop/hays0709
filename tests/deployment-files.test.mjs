import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const root = new URL("../", import.meta.url);
const read = (relativePath) => readFileSync(new URL(relativePath, root), "utf8");

assert.equal(existsSync(new URL("scripts/deploy.sh", root)), true, "deploy script should exist");
assert.equal(existsSync(new URL("deploy/nginx.conf.template", root)), true, "nginx template should exist");

const deploy = read("scripts/deploy.sh");
const nginx = read("deploy/nginx.conf.template");
const readme = read("README.md");

for (const flag of ["--domain", "--branch", "--repo-url", "--https", "--email", "--rollback"]) {
  assert.match(deploy, new RegExp(flag.replaceAll("-", "\\-")), `${flag} should be documented by the script`);
}

assert.match(deploy, /RELEASES_DIR=.*releases/);
assert.match(deploy, /current/);
assert.match(deploy, /previous/);
assert.match(deploy, /nginx -t/);
assert.match(deploy, /curl[\s\S]*--resolve/);
assert.match(deploy, /--keep-until-expiring/);
assert.match(deploy, /今天的班/);

for (const placeholder of ["__DOMAIN__", "__SITE_ROOT__", "__INDEX_FILE__"]) {
  assert.match(nginx, new RegExp(placeholder.replaceAll("_", "\\_")), `${placeholder} should be present`);
}

assert.match(nginx, /gzip on;/);
assert.match(nginx, /Cache-Control/);
assert.match(nginx, /X-Content-Type-Options/);
assert.match(nginx, /Referrer-Policy/);

for (const documentationMarker of [
  "sudo bash scripts/deploy.sh --domain",
  "--https --email",
  "--rollback",
  "systemctl",
  "80",
  "443",
  "今天的班"
]) {
  assert.match(readme, new RegExp(documentationMarker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")), `${documentationMarker} should be documented`);
}
