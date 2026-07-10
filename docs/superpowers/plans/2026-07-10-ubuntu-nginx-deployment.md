# Ubuntu Nginx Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repeatable Ubuntu/Nginx deployment path for the H5 and its same-origin AI proxy, document its operation, and verify the deployment contract before pushing it.

**Architecture:** A Bash script shallow-clones the selected Git ref into a temporary directory, validates and publishes the H5 runtime files plus `server.mjs` into timestamped releases under `/opt/hays0709`, then atomically swaps the `current` symlink. Nginx serves the stable symlink and proxies `/api/fortune` to a loopback systemd service, while Certbot remains an optional HTTPS step.

**Tech Stack:** Bash, Ubuntu `apt`/`systemd`, Git, rsync, Nginx, Node.js 18+, curl, optional Certbot, Node.js assertion tests.

---

### Task 1: Add deployment contract tests

**Files:**
- Create: `tests/deployment-files.test.mjs`

- [ ] **Step 1: Write the failing test**

  Add assertions that `scripts/deploy.sh`, `deploy/nginx.conf.template`, and `README.md` exist and contain the required CLI flags, release paths, Nginx placeholders, health-check marker, HTTPS behavior, and rollback instructions.

- [ ] **Step 2: Run test to verify it fails**

  Run: `node tests/deployment-files.test.mjs`

  Expected: FAIL because the deployment files and updated documentation do not exist yet.

- [ ] **Step 3: Commit the red test**

  Run: `git add tests/deployment-files.test.mjs && git commit -m "test: define nginx deployment contract"`

### Task 2: Create the Nginx template

**Files:**
- Create: `deploy/nginx.conf.template`

- [ ] **Step 1: Write the minimal template**

  Add placeholders `__DOMAIN__`, `__SITE_ROOT__`, and `__INDEX_FILE__`; serve the launch-cabin HTML as the index, return 404 for unknown paths, cache image/SVG/font assets for seven days, enable the specified gzip types, and add only the agreed `nosniff` and referrer headers.

- [ ] **Step 2: Validate the template contract**

  Run: `node tests/deployment-files.test.mjs`

  Expected: still FAIL only for the missing deployment script or README requirements.

- [ ] **Step 3: Commit the template**

  Run: `git add deploy/nginx.conf.template && git commit -m "feat: add nginx site template"`

### Task 3: Implement the Ubuntu deployment script

**Files:**
- Create: `scripts/deploy.sh`

- [ ] **Step 1: Add argument parsing and prerequisites**

  Implement `--domain`, `--branch`, `--repo-url`, `--https`, `--email`, `--keep-releases`, `--rollback`, and `--help`; enforce root execution, ASCII FQDN validation, Ubuntu package checks, and safe temporary-directory cleanup.

- [ ] **Step 2: Add release publication**

  Shallow-clone the requested ref, require the two HTML files plus `assets/`, rsync only the runtime allowlist into `/opt/hays0709/releases/<timestamp>`, create or rotate `current`/`previous`, and retain current/previous plus three additional releases by default.

- [ ] **Step 3: Add Nginx configuration and lifecycle handling**

  Create the managed Nginx configuration only when absent, preserve Certbot-managed files on later deployments, validate with `nginx -t`, use `systemctl enable --now nginx` when inactive or reload when active, and restore a backup on configuration failure.

- [ ] **Step 4: Add health checks, HTTPS, and rollback**

  Use `curl --resolve` against the configured virtual host; require HTTP 200 plus `今天的班` for HTTP-only sites, or HTTP redirect plus HTTPS 200 for HTTPS sites. Install and run Certbot only with an explicit email, preserve valid certificates with `--keep-until-expiring`, and swap `current`/`previous` for rollback with recovery on failed health checks.

- [ ] **Step 5: Run syntax and contract checks**

  Run: `bash -n scripts/deploy.sh` and `node tests/deployment-files.test.mjs`

  Expected: shell syntax passes and the deployment contract test passes.

- [ ] **Step 6: Commit the script**

  Run: `git add scripts/deploy.sh && git commit -m "feat: add Ubuntu nginx deploy script"`

### Task 4: Update the operator documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document prerequisites and DNS**

  Explain Ubuntu 22.04+, sudo/systemd/apt, GitHub access, DNS A/AAAA records, and ports 80/443.

- [ ] **Step 2: Document deployment operations**

  Add copy-paste commands for first HTTP deployment, first HTTPS deployment, repeat deployment, explicit branch/repository, rollback, logs, configuration checks, and common failures. State that secrets and certificates stay on the server.

- [ ] **Step 3: Run documentation contract tests**

  Run: `node tests/deployment-files.test.mjs`

  Expected: PASS.

- [ ] **Step 4: Commit the documentation**

  Run: `git add README.md && git commit -m "docs: document Ubuntu nginx deployment"`

### Task 5: Verify the complete change

**Files:**
- Modify: none unless a verification defect is found.

- [ ] **Step 1: Run all repository tests**

  Run: `Get-ChildItem tests -Filter *.test.mjs | ForEach-Object { node $_.FullName }`

  Expected: every assertion test exits successfully.

- [ ] **Step 2: Run static checks**

  Run: `bash -n scripts/deploy.sh`; `git diff --check`; inspect `git status --short`.

  Expected: no shell syntax error, no whitespace errors, and only intended files changed.

- [ ] **Step 3: Review the final diff**

  Run: `git diff origin/main...HEAD --stat`; `git diff origin/main...HEAD -- README.md scripts/deploy.sh deploy/nginx.conf.template tests/deployment-files.test.mjs`.

  Expected: the diff contains only deployment script, Nginx template, tests, documentation, and committed design/plan records.

### Task 6: Push the finished work

- [ ] **Step 1: Confirm remote and branch state**

  Run: `git status --short --branch`; `git remote -v`; `git log --oneline origin/main..HEAD`.

  Expected: clean worktree, expected GitHub origin, and only the intended local commits ahead of `origin/main`.

- [ ] **Step 2: Push the main branch**

  Run: `git push origin main`

  Expected: remote `main` advances to the verified local HEAD.

- [ ] **Step 3: Verify remote ancestry**

  Run: `git fetch origin main`; `git rev-parse HEAD`; `git rev-parse origin/main`.

  Expected: both hashes match.
