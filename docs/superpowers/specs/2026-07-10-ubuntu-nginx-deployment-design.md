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

The script will use `/opt/hays0709` as its application root. Each deployment clones the requested branch into a temporary directory, validates the entry page and assets, copies only runtime site files into a new timestamped release, and atomically switches the `current` symlink. The previous `current` target is saved as `previous`; older releases are pruned after the switch while retaining enough history for one rollback.

The Nginx template will point its `root` at `/opt/hays0709/current`, configure the Chinese entry filename as the index, return a clear 404 for missing paths, cache image assets, enable safe compression, and add low-risk security headers. The domain is substituted at deployment time. HTTPS is an optional Certbot step after the HTTP site has passed its health check.

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

The repository URL defaults to the project's GitHub origin, but the script will allow an explicit URL when a mirror is needed. The script will fail early if the domain is missing, required Ubuntu commands are unavailable, the remote cannot be cloned, the entry page/assets are missing, or `nginx -t` fails.

## Error handling and safety

- Use `set -Eeuo pipefail` and a cleanup trap for temporary checkouts.
- Do not alter the live `current` link until the new release is fully copied and the generated Nginx configuration is syntactically valid.
- Write the Nginx file to a temporary path and move it into place only after validation.
- Require `--email` when `--https` is requested; do not guess a certificate contact.
- Keep deployment paths under `/opt/hays0709` and remove only old release directories created by this deployment.
- If the health check fails after switching, restore the prior symlink and reload the last known-good Nginx configuration.

## Verification

Local verification will run the repository's existing Node assertion tests, a shell syntax check, and static checks that the deployment script, Nginx template, and README contain the required operator paths. Server-side verification will run `nginx -t`, `systemctl is-active nginx`, and a loopback HTTP request with the configured Host header.

## Files

- `scripts/deploy.sh`: Ubuntu deployment, HTTPS option, rollback, validation, and release retention.
- `deploy/nginx.conf.template`: Nginx server block template with deployment placeholders.
- `README.md`: user-facing setup and operating instructions.
- `tests/deployment-files.test.mjs`: regression checks for the deployment contract and documentation.
