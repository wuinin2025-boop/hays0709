import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const root = new URL("../", import.meta.url);
const read = (relativePath) => readFileSync(new URL(relativePath, root), "utf8");

assert.equal(existsSync(new URL("scripts/deploy.sh", root)), true, "deploy script should exist");
assert.equal(
  existsSync(new URL("scripts/configure-xray-fallback.sh", root)),
  true,
  "Xray fallback helper should exist"
);
assert.equal(existsSync(new URL("deploy/nginx.conf.template", root)), true, "nginx template should exist");
assert.equal(
  existsSync(new URL("deploy/hays0709.service.template", root)),
  true,
  "systemd service template should exist"
);

const deploy = read("scripts/deploy.sh");
const xrayFallback = read("scripts/configure-xray-fallback.sh");
const nginx = read("deploy/nginx.conf.template");
const service = read("deploy/hays0709.service.template");
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
assert.match(deploy, /detect_https_port_conflict/);
assert.match(deploy, /ss[\s\S]*443/);
assert.match(deploy, /Port 443 is occupied/);
assert.match(deploy, /configure-xray-fallback\.sh/);
assert.match(deploy, /ensure_node_runtime/);
assert.match(deploy, /setup_22\.x/);
assert.match(deploy, /server\.mjs/);
assert.match(deploy, /hays0709\.service/);
assert.match(deploy, /systemctl[\s\S]*daemon-reload/);
assert.match(deploy, /systemctl restart "\$SERVICE_NAME"/);
assert.match(deploy, /APP_PATH="\/hays"/);
assert.match(deploy, /api_proxy_health_check/);
assert.match(deploy, /public_api_health_check/);
assert.match(deploy, /seq 1 20/);
assert.match(deploy, /\/api\/fortune/);
assert.match(deploy, /\$APP_PATH\//);
assert.match(deploy, /ensure_nginx_hays_path/);
assert.match(deploy, /--include='server\.mjs'/);
const mainBody = deploy.match(/main\(\)\s*\{([\s\S]*?)\n\}/)?.[1] ?? "";
assert.match(deploy, /ensure_https_packages/);
assert.ok(
  mainBody.indexOf("ensure_packages") < mainBody.indexOf("detect_https_port_conflict") &&
    mainBody.indexOf("detect_https_port_conflict") < mainBody.indexOf("ensure_https_packages"),
  "base tools should be installed before detecting port 443, and Certbot only after the conflict check"
);
assert.ok(
  mainBody.indexOf("install_app_service") < mainBody.indexOf("rollback_release"),
  "rollback should install or refresh the systemd service before restarting the previous release"
);

for (const flag of ["--domain", "--x-ui-db", "--http1-port", "--http2-port"]) {
  assert.match(xrayFallback, new RegExp(flag.replaceAll("-", "\\-")), `${flag} should be supported by the Xray helper`);
}

assert.match(xrayFallback, /location \^~ \/api\/fortune/);
assert.match(xrayFallback, /proxy_pass http:\/\/127\.0\.0\.1:5173/);
assert.match(xrayFallback, /APP_PATH="\/hays"/);

for (const marker of [
  "inbound_fallbacks",
  "sqlite3",
  "connection.backup",
  "127.0.0.1",
  "8443",
  "8444",
  "nginx -t",
  "systemctl stop x-ui",
  "-wal",
  "-shm",
  "systemctl restart x-ui",
  "wait_for_xray_listener",
  "seq 1 30",
  "curl --http1.1",
  "curl --http2-prior-knowledge",
  "$APP_PATH/",
  "rollback"
]) {
  assert.match(xrayFallback, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")), `${marker} should be handled by the Xray helper`);
}

for (const placeholder of ["__DOMAIN__", "__SITE_ROOT__", "__INDEX_FILE__"]) {
  assert.match(nginx, new RegExp(placeholder.replaceAll("_", "\\_")), `${placeholder} should be present`);
}

assert.match(nginx, /gzip on;/);
assert.match(nginx, /location \^~ \/api\/fortune/);
assert.match(nginx, /proxy_pass http:\/\/127\.0\.0\.1:5173/);
assert.match(nginx, /location = \/ \{/);
assert.match(nginx, /return 302 \/hays\/;/);
assert.match(nginx, /location = \/hays \{/);
assert.match(nginx, /return 301 \/hays\/;/);
assert.match(nginx, /location = \/hays\/ \{/);
assert.match(nginx, /location \^~ \/hays\/assets\//);
assert.match(nginx, /location \^~ \/hays\//);
assert.match(nginx, /rewrite \^\/hays\/\(\.\*\)\$ \/\$1 break;/);
assert.match(nginx, /proxy_read_timeout 60s/);
assert.match(nginx, /Cache-Control/);
assert.match(nginx, /X-Content-Type-Options/);
assert.match(nginx, /Referrer-Policy/);

for (const marker of [
  "WorkingDirectory=/opt/hays0709/current",
  "EnvironmentFile=-/etc/hays0709.env",
  "ExecStart=/usr/bin/node /opt/hays0709/current/server.mjs",
  "Restart=on-failure",
  "User=www-data"
]) {
  assert.match(service, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")), `${marker} should be configured`);
}

for (const documentationMarker of [
  "sudo bash scripts/deploy.sh --domain",
  "--https --email",
  "--rollback",
  "systemctl",
  "80",
  "443",
  "今天的班",
  "x-ui/Xray",
  "configure-xray-fallback.sh",
  "8443",
  "8444",
  "/hays/",
  "/etc/hays0709.env",
  "systemctl status hays0709",
  "server.mjs",
  "/api/fortune"
]) {
  assert.match(readme, new RegExp(documentationMarker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")), `${documentationMarker} should be documented`);
}

assert.match(xrayFallback, /location \^~ \/api\/fortune/);
