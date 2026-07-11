# Hays Path Deployment Design

## Goal

Serve the Hays H5 under `https://wuininyyy2026.xyz/hays/` while keeping the existing VPN/Xray service on public port `443`.

## Routing

- `GET /hays` returns `301 /hays/`.
- `GET /hays/` serves `瀚纳仕H5 demo-启动舱.html`.
- `GET /hays/assets/...` serves files from the existing `assets/` directory.
- `GET /` returns `302 /hays/` so the old root entry still reaches Hays for now.
- `GET /api/fortune` and `GET /api/fortune/status` stay at the domain root to avoid changing frontend API code.
- Unknown root-level page paths return `404`, leaving room for future projects under their own prefixes.

## Deployment

The normal Nginx template and the Xray fallback helper must generate the same path-based Hays routing. Existing managed Nginx configs must be upgraded during `scripts/deploy.sh`, because the current production server already has a managed Xray fallback config and later deploys should not require manual Nginx editing.

## Verification

Deployment health checks must request `/hays/` for the page marker and `/api/fortune/status` for the AI proxy. Xray fallback verification must test both loopback HTTP/1.1 and h2c listeners at `/hays/`, then test public HTTPS at `/hays/`.

## Non-goals

This change does not move the AI API to `/hays/api`, does not apply for a wildcard certificate, and does not change Xray client credentials or public VPN access.
