# Ubuntu Nginx Deployment Design

## Context

`hays0709` is a static H5 site. The production page is `瀚纳仕H5 demo-启动舱.html` and its runtime assets are under `assets/`. There is no Node.js build, server process, database, or runtime configuration required by the site.

The deployment needs to be repeatable on an Ubuntu server with an existing domain, and it must be safe to update without exposing a partially copied release.

## Goals

- Serve the H5 through native Ubuntu Nginx.
- Let the operator provide the domain at deploy time instead of committing a domain to the repository.
- Pull a selected Git branch from GitHub and publish an atomic release.
- Keep the current release and a previous release so a failed update can be rolled back.
- Validate Nginx configuration and the local HTTP response before reporting success.
- Document DNS, first deployment, HTTPS, updates, rollback, logs, and common failures.

## Non-goals

- Managing DNS records through a provider API.
- Storing TLS private keys or server credentials in Git.
- Introducing Docker, Node.js, a backend API, or a database.
- Changing the H5's product behavior or visual design.

## Selected architecture

Use a Bash deployment script plus an Nginx configuration template:

```text
GitHub main branch
        |
        | shallow clone into a temporary directory
        v
/opt/hays0709/releases/<timestamp>/  <- immutable published files
        ^
        |
/opt/hays0709/current                <- atomically swapped symlink
        ^
        |
Nginx /etc/nginx/sites-enabled/hays0709.conf
```

The script will use `/opt/hays0709` as its application root. Each deployment shallow-clones the requested Git branch or tag into a temporary directory, validates the entry page and assets, copies only runtime site files into a new timestamped release, and atomically switches the `current` symlink. The default ref is `main`; `--branch` accepts a Git branch or tag name and rejects empty values or values beginning with `-`. The previous `current` target is saved as `previous`; older release directories matching the script's timestamp naming pattern are pruned while retaining the current release, the previous release, and the three most recent additional releases.

The runtime allowlist is the two root-level `*.html` files and the complete `assets/` directory. The release excludes `.git/`, `.playwright-cli/`, `output/`, `tests/`, `scripts/`, `deploy/`, `docs/`, and `README.md`, so test artifacts and deployment tooling are not served publicly.

The Nginx template will point its `root` at `/opt/hays0709/current`, configure the Chinese entry filename as the index, return a clear 404 for missing paths, cache image assets, enable safe compression, and add low-risk security headers. The domain is substituted at deployment time. HTTPS is an optional Certbot step after the HTTP site has passed its health check.

The first deployment creates `/etc/nginx/sites-available/hays0709.conf` and its `sites-enabled` symlink from the template. Later deployments never regenerate that file: the root already points at the stable `current` symlink, and this preserves Certbot's managed TLS directives. If an existing configuration has a different `server_name`, the script stops and asks the operator to resolve the domain mismatch instead of overwriting it. When a new configuration is created, it is installed to a temporary path, tested with `nginx -t`, and restored or removed if validation fails.

## Operator interface

First deployment:

```bash
git clone https://github.com/wuinin2025-boop/hays0709.git
cd hays0709
sudo bash scripts/deploy.sh --domain example.com
```

HTTPS deployment:

```bash
sudo bash scripts/deploy.sh --domain example.com --https --email admin@example.com
```

Subsequent deployment and rollback:

```bash
sudo bash scripts/deploy.sh --domain example.com --branch main
sudo bash scripts/deploy.sh --domain example.com --rollback
```

The explicit repository option is `--repo-url URL`. It defaults to the `origin` URL of the checkout containing the script, or to `https://github.com/wuinin2025-boop/hays0709.git` when the script is copied outside a Git checkout. The script will fail early if the domain is missing, the domain contains unsafe characters, required Ubuntu commands are unavailable, the remote/ref cannot be cloned, the entry page/assets are missing, or `nginx -t` fails.

## Error handling and safety

- Use `set -Eeuo pipefail` and a cleanup trap for temporary checkouts.
- Do not alter the live `current` link until the new release is fully copied and any newly generated Nginx configuration is syntactically valid.
- Write a new Nginx file to a temporary path, preserve an existing file in `/opt/hays0709/config-backups/`, and restore the prior file if validation fails.
- Require `--email` when `--https` is requested; do not guess a certificate contact.
- Keep deployment paths under `/opt/hays0709` and remove only old release directories created by this deployment, identified by the script's timestamp pattern. On a first deployment there is no `previous` link and rollback exits with an explanatory error. On later deployments, `current` and `previous` are swapped so rollback can itself be reversed.
- If the health check fails after switching, restore the prior symlink and reload the last known-good Nginx configuration. If no prior release exists, remove the failed `current` link and leave the validated Nginx configuration in place.

## Verification

Local verification will run the repository's existing Node assertion tests, a shell syntax check, and static checks that the deployment script, Nginx template, and README contain the required operator paths. Server-side verification will run `nginx -t`, `systemctl is-active nginx`, and a loopback HTTP request with the configured Host header; the response must be HTTP 200 and contain `今天的班`. With `--https`, the script first checks local HTTP before Certbot and then checks `https://<domain>/` for HTTP 200 and the same page marker after certificate installation.

Acceptance matrix:

| Scenario | Expected result |
| --- | --- |
| First HTTP deployment | New release, `current` link, Nginx config, active Nginx, HTTP 200 with launch-page marker |
| Repeat deployment | New release and `previous` link; existing Certbot-managed Nginx directives remain unchanged |
| Failed clone/validation/config test | Non-zero exit and no change to the live `current` link |
| Failed post-switch health check | Previous release restored and Nginx reloaded |
| Rollback after at least two releases | `current` and `previous` swap and HTTP health check still passes |
| First-deployment rollback | Non-zero exit with a clear “no previous release” message |
| HTTPS deployment | Certbot runs only with an explicit email, HTTP redirects, HTTPS returns the launch page |

## Files

- `scripts/deploy.sh`: Ubuntu deployment, HTTPS option, rollback, validation, and release retention.
- `deploy/nginx.conf.template`: Nginx server block template with deployment placeholders.
- `README.md`: user-facing setup and operating instructions.
- `tests/deployment-files.test.mjs`: regression checks for the deployment contract and documentation.
