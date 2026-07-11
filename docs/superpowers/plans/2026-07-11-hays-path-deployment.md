# Hays Path Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Hays browser access to `/hays/` while preserving VPN/Xray coexistence and the existing root API proxy.

**Architecture:** Nginx owns path routing. Xray continues to terminate public TLS and fallback browser traffic to loopback Nginx listeners. The deployment script updates existing managed configs and validates the `/hays/` page path plus `/api/fortune/status`.

**Tech Stack:** Bash deployment scripts, Nginx, x-ui/Xray fallback config, Node.js built-in assertion tests.

## Global Constraints

- Public Hays page URL is `https://wuininyyy2026.xyz/hays/`.
- Root `/` redirects to `/hays/`.
- API remains `/api/fortune` and `/api/fortune/status`.
- Public port `443` remains owned by Xray on servers using x-ui.
- No API keys or VPN credentials are committed.

---

### Task 1: Lock Path-Based Deployment Behavior

**Files:**
- Modify: `tests/deployment-files.test.mjs`

**Interfaces:**
- Consumes: existing deployment script/template text checks.
- Produces: assertions requiring `/hays/` routes and health checks.

- [x] **Step 1: Write the failing test**

Add assertions for `APP_PATH="/hays"`, root redirect, `/hays` redirect, `/hays/` page location, `/hays/assets/` asset location, deploy upgrade helper, and Xray verification at `$APP_PATH/`.

- [x] **Step 2: Run test to verify it fails**

Run: `node tests/deployment-files.test.mjs`
Expected: FAIL because `APP_PATH="/hays"` is missing.

### Task 2: Implement Nginx Path Routing

**Files:**
- Modify: `deploy/nginx.conf.template`
- Modify: `scripts/configure-xray-fallback.sh`

**Interfaces:**
- Consumes: `INDEX_FILE`, `SITE_ROOT`, `APP_PATH`.
- Produces: root redirect, `/hays/` page serving, `/hays/assets/` serving, and API proxy unchanged.

- [ ] **Step 1: Update the plain Nginx template**

Add exact `/`, exact `/hays`, exact `/hays/`, `/hays/assets/`, and `/hays/` locations while preserving `/api/fortune`.

- [ ] **Step 2: Update the Xray fallback helper**

Add `APP_PATH="/hays"` and generate the same routing in its loopback Nginx config.

- [ ] **Step 3: Update Xray verification URLs**

Change fallback verification requests from `/` to `$APP_PATH/`.

### Task 3: Make Existing Managed Configs Upgradeable

**Files:**
- Modify: `scripts/deploy.sh`

**Interfaces:**
- Consumes: an existing managed `/etc/nginx/sites-available/hays0709.conf`.
- Produces: an upgraded config containing `/hays/` routes without replacing Xray loopback listeners.

- [ ] **Step 1: Add `APP_PATH="/hays"`**

Use it in health checks and completion output.

- [ ] **Step 2: Add `ensure_nginx_hays_path`**

If the managed config lacks `/hays` routing, back it up, replace the old root `try_files` location with path routing, validate with `nginx -t`, and restore on validation failure.

- [ ] **Step 3: Call the upgrade helper**

Run it after `ensure_nginx_api_proxy` for existing configs.

- [ ] **Step 4: Update page health checks**

Check `$APP_PATH/` for the page marker and keep `/api/fortune/status` unchanged.

### Task 4: Document, Verify, Commit, Push, Deploy

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: updated scripts and production domain.
- Produces: clear commands and current access URLs.

- [ ] **Step 1: Update README URLs**

Document `https://wuininyyy2026.xyz/hays/`, root redirect, and Xray coexistence update flow.

- [ ] **Step 2: Run all local tests**

Run: `for t in tests/*.test.mjs; do node "$t" || exit 1; done`
Expected: all tests exit `0`.

- [ ] **Step 3: Commit and push**

Commit with `feat: serve hays under path prefix` and push `main` to `origin`.

- [ ] **Step 4: Deploy on server**

Run the updated deployment on the server, then verify public `/hays/`, `/hays`, `/`, `/api/fortune/status`, Xray listener, and Nginx loopback listeners.
